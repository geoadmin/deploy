#!/bin/bash
#
# script for database and table managment on streaming replication master
# p.e.
# copy databases                        [ -s database   -t target   ]
# copy tables                           [ -s table      -t target   ]
# archive/snapshot bod                  [ -s bod_master -a 20150303 ]
MY_DIR=$(dirname $(readlink -f $0))
source "${MY_DIR}/includes.sh"

display_usage() {
    echo -e "Usage:\n$0 -s source_objects -t target_staging -a timestamp for BOD snapshot/archive (YYYYMMDD)"
    echo -e "\t-s comma delimited list of source databases and/or tables - mandatory"
    echo -e "\t-t target staging - mandatory choose one of '${targets}'"
    echo -e "\t-a is optional and only valid for BOD, if you dont enter a target the script will just create an archive/snapshot copy of the bod\n"
}

while getopts ":s:t:a:" options; do
    case "${options}" in
        s)
            source_objects=${OPTARG}
            IFS=',' read -ra array_source <<< "${source_objects}"
            ;;
        t)
            target=${OPTARG}
            ;;
        a)
            timestamp=${OPTARG}
            ;;
        \? )
            display_usage 1>&5 2>&6
            exit 1
            ;;
        *)
            display_usage 1>&5 2>&6
            exit 1
            ;;
    esac
done

#######################################
# pre-copy checks for tables
# Globals:
#   target_id
#   source_db
#   source_schema
#   source_table
#   target_db
#   target_schema
#   target_table
#   referencing_tables
#   referencing_tables_sql
# Arguments:
#   None
# Returns:
#   None
#######################################
check_table() {
    # check if source table exists, views cannot be deployed
    if [[ -z $(psql -lqt -h localhost -c "SELECT table_catalog||'.'||table_schema||'.'||table_name FROM information_schema.tables where lower(table_type) not like 'view'" -d ${source_db}  2> /dev/null | egrep "\b${source_id}\b") ]]; then
        echo "source table does not exist ${source_id} " >&2
        exit 1
    fi

    # check if target table exists 
    if [[ -z $(psql -lqt -h localhost -c "SELECT table_catalog||'.'||table_schema||'.'||table_name FROM information_schema.tables where lower(table_type) not like 'view'" -d ${target_db}  2> /dev/null | egrep "\b${target_id}\b") ]]; then
        "target table does not exist ${target_id}." >&2
        exit 1
    fi

    # check if source and target table have the same structure (column name and data type)
    source_columns=$(psql -h localhost -d ${source_db} -Atc "select column_name,data_type FROM information_schema.columns WHERE table_schema = '${source_schema}' AND table_name = '${source_table}' order by 1;")
    target_columns=$(psql -h localhost -d ${target_db} -Atc "select column_name,data_type FROM information_schema.columns WHERE table_schema = '${target_schema}' AND table_name = '${target_table}' order by 1;")
    if [ ! "${source_columns}" == "${target_columns}" ]; then
        echo "structure of source and target table is different." >&2
        exit 1
    fi
    
    # get count of referencing tables/constraints, skip table if it is referenced by other tables
    referencing_tables_sql="
    SELECT count(1)
        FROM pg_catalog.pg_constraint r
        WHERE  r.contype = 'f' 
        AND conrelid::regclass != confrelid::regclass
        AND confrelid::regclass = '${source_schema}.${source_table}'::regclass;
    "
    referencing_tables=$(psql -qAt -h localhost -d ${source_db} -c "${referencing_tables_sql}")
    if [ ${referencing_tables} -gt 0 ]; then 
        echo "cannot copy table ${source_id}, table is referenced by ${referencing_tables} objects, use db_copy instead." >&2
        continue
    fi
}

#######################################
# pre-copy checks for databases
# Globals:
#   source_db
# Arguments:
#   None
# Returns:
#   None
#######################################
check_database() {
    # check if source database exists
    if [[ -z $(psql -lqt -h localhost | egrep "\b${source_db}\b" 2> /dev/null) ]]; then
        echo "No existing databases are named ${source_db}." >&2
        eNonexit 1
    fi
}

#######################################
# create archive/snapshot copy of bod
# Globals:
#   source_db
#   timestamp
# Arguments:
#   None
# Returns:
#   None
#######################################
bod_create_archive() {
    #BOD archiving
    if [[ ${source_db%_*} == bod ]]; then
        if [[ ${#timestamp} > 0 ]]; then
            if [[ ! ${timestamp} =~ (^[a-zA-Z0-9]+$)  ]]; then
                echo "timestamp must match the pattern [a-zA-Z0-9]+"  >&2
                exit 1
            fi             
            archive_bod="${source_db}${timestamp}"
            echo "Archiving ${source_db} as ${archive_bod}..."
            psql -h localhost -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${archive_bod}';" >/dev/null
            dropdb -h localhost --if-exists ${archive_bod} &> /dev/null 
            psql -h localhost -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${source_db}';" >/dev/null
            createdb -h localhost -O postgres --encoding 'UTF-8' -T ${source_db} ${archive_bod} >/dev/null
            psql -d template1 -h localhost -c "COMMENT ON DATABASE ${archive_bod} IS 'snapshot/archive copy from ${source_db} on $(date '+%F %T') with command ${COMMAND} by user ${USER}';" > /dev/null
            if [[ ! -z "${ArchiveMode}" ]]; then
                # skip rest of loop if we are in pure archive mode (bod-only)
                continue
            fi
        else
            echo "Not archiving"
        fi  
    fi
}

#######################################
# pre-copy checks for source and target objects
# Globals:
#   target
#   source_db
#   target_db
# Arguments:
#   None
# Returns:
#   None
#######################################
check_source() {
    #check if source and target are the same
    if [[ "${target_db}" == "${source_db}" ]]; then
        echo "You may not copy a db or table over itself. You have '${source_db}' as source, with target '${target}'." >&2
        exit 1
    fi
    
    #check if master is the source and, if not, ask for confirmation
    if [[ ! ${source_db} == *_master ]]; then
        echo -n "Master is not the selected source. Do you want to continue? (y/n)"
        echo
        read answer
        if [ ! "${answer}" == "y" ]; then
            echo "deploy aborted"
            exit 1
        fi
    fi
}

#######################################
# copy database
# Globals:
#   source_db
#   target_db
#   target_db_tmp
#   attached_slaves
# Arguments:
#   None
# Returns:
#   None
#######################################
copy_database() {
    size=$(psql -qAt -h localhost -d ${source_db} -c "SELECT pg_size_pretty(pg_database_size('"${source_db}"'));")
    
    echo "copy ${source_db} to ${target_db} size: ${size} attached slaves: ${attached_slaves}"
    echo "creating temporary database ${target_db_tmp} ..."
    psql -h localhost -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${target_db_tmp}';" >/dev/null
    dropdb -h localhost --if-exists ${target_db_tmp} &> /dev/null
    psql -h localhost -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${source_db}';" >/dev/null
    createdb -h localhost -O postgres --encoding 'UTF-8' -T ${source_db} ${target_db_tmp} >/dev/null

    echo "replacing ${target_db} with ${target_db_tmp} ..."
    psql -h localhost -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${target_db}';" >/dev/null
    dropdb -h localhost --if-exists ${target_db} &>/dev/null
    psql -h localhost -d template1 -c "alter database ${target_db_tmp} rename to ${target_db};" >/dev/null 

    # add some metainformation to the copied database as comment
    psql -d template1 -h localhost -c "COMMENT ON DATABASE ${target_db} IS 'copied from ${source_db} on $(date '+%F %T') with command ${COMMAND} by user ${USER}';" > /dev/null

    # set database to read-only if it is not a _master database
    if [[ ! ${target} == master ]]; then
        psql -h localhost -d template1 -c "alter database ${target_db} SET default_transaction_read_only = on;" >/dev/null
    else
        psql -h localhost -d template1 -c "alter database ${target_db} SET default_transaction_read_only = off;" >/dev/null
    fi
}

#######################################
# copy table
# Globals:
#   source_db
#   source_schema
#   source_table
#   source_id
#   target_db
#   target_schema
#   target_table
#   target_id
#   attached_slaves
# Arguments:
#   None
# Returns:
#   None
#######################################
copy_table() {
    # remove read only transaction from database
    psql -h localhost -d template1 -c "alter database ${target_db} SET default_transaction_read_only = off;" >/dev/null
    # get primary keys for table sorting
    primary_keys_sql="SELECT string_agg(a.attname,', ')
    FROM   pg_index i
    JOIN   pg_attribute a ON a.attrelid = i.indrelid
                         AND a.attnum = ANY(i.indkey)
    WHERE  i.indrelid = '${source_schema}.${source_table}'::regclass
    AND    i.indisprimary;
    "
    primary_keys=$(psql -qAt -h localhost -d ${source_db} -c "${primary_keys_sql}")

    jobs=${CPUS}
    rows=$(psql -qAt -h localhost -d ${source_db} -c "SELECT count(1) FROM ${source_schema}.${source_table};")
    size=$(psql -qAt -h localhost -d ${source_db} -c "SELECT pg_size_pretty(pg_total_relation_size('"${source_schema}.${source_table}"'));")
    increment=$( Ceiling ${rows} ${jobs} )
    # no multithreading if less than 1000 rows
    if [ "${rows}" -lt 1000 ]; then 
        jobs=1
        increment=${rows}
    fi
    echo "multithread copy ${source_id} to ${target_id} rows: ${rows} threads: ${jobs} rows/thread: ${increment} size: ${size} attached slaves: ${attached_slaves}" 

    echo "drop indexes on ${target_id}"
    (pg_dump -h localhost --if-exists -c -t ${source_schema}.${source_table} -s ${source_db} 2>/dev/null | egrep "\bDROP INDEX\b" | psql -d "${target_db}" -h localhost 2>/dev/null ) || true

    # populate array with foreign key constraints on target table
    declare -A foreign_keys=( )
    while IFS=$'\|' read -a Record; do
        foreign_keys["${Record[0]}"]="${Record[1]}"
    done < <(
    psql -h localhost --quiet --no-align  -t -c "
    SELECT conname,
        pg_catalog.pg_get_constraintdef(r.oid, true) as condef
    FROM pg_catalog.pg_constraint r
    WHERE r.conrelid = '${target_schema}.${target_table}'::regclass AND r.contype = 'f' ORDER BY 1;" ${target_db} 2>/dev/null
    )

    if [ "${#foreign_keys[@]}" -gt 0 ]; then
        for i in "${!foreign_keys[@]}"
        do
            echo "DROP FOREIGN KEY CONSTRAINT ${i} FROM ${target_id} ..."
            echo "ALTER TABLE IF EXISTS ONLY ${target_schema}.${target_table} DROP CONSTRAINT IF EXISTS ${i};" | psql -h localhost -d ${target_db} &> /dev/null
        done
    fi

    echo "truncate table ${target_id}"
    ( psql -h localhost -c "begin; TRUNCATE TABLE ${target_schema}.${target_table}; commit;" -d "${target_db}" )

    (
    for ((i=1; i<=${jobs}; i++)); do
        offset=$(echo "((${i}-1)*${increment})" | bc)
        if [ $((offset+${increment})) -gt ${rows} ]; then counter=${rows}; else counter=$((offset+${increment}));fi
        echo "dumping ${offset}..${counter}"
        ( psql -h localhost -qAt -d ${source_db} -c "COPY ( SELECT * FROM ${source_schema}.${source_table} order by ${primary_keys:=1} asc offset ${offset} limit ${increment} ) TO STDOUT with csv" | psql -h localhost -qAt -d ${target_db} -c "SET session_replication_role = replica; COPY ${target_schema}.${target_table} from stdin with csv; SET session_replication_role = DEFAULT;" )& pids="${pids} $!"
    done;  
    wait ${pids} 2> /dev/null
    )

    echo "create indexes on ${target_id}"
    ( pg_dump -h localhost --if-exists -c -t ${source_schema}.${source_table} -s ${source_db} 2>/dev/null | egrep -i "\bcreate\b" | egrep -i "\bindex\b" | sed "s/^/set search_path = ${source_schema}, public, pg_catalog; /" | sed "s/'/\\\'/g" | xargs --max-procs=${jobs} -I '{}' sh -c 'psql -h localhost -d $@ -c "{}"' -- "${target_db}" ) || true 

    if [ "${#foreign_keys[@]}" -gt 0 ]; then
        for i in "${!foreign_keys[@]}"
        do
            echo "CREATE FOREIGN KEY CONSTRAINT ${i} ON ${target_id} ..."
            echo "ALTER TABLE ONLY ${target_schema}.${target_table} ADD CONSTRAINT ${i} ${foreign_keys[${i}]};" | psql -h localhost -d ${target_db} &> /dev/null
        done
    fi

    # add read only transaction to database if target is not master
    if [[ ! ${target} == master ]]; then
        psql -h localhost -d template1 -c "alter database ${target_db} SET default_transaction_read_only = on;" >/dev/null
    fi
}

echo "start ${COMMAND}"
CPUS=$(grep "processor" < /proc/cpuinfo | wc -l) || CPUS=1
START=$(date +%s%3N)

# if source_object is bod and target is empty and timestamp is present and source_object does not contain any ","
if [[ ${source_objects%_*} == bod && -z "${target}" && ! -z "${timestamp}" && ! "${source_objects}" = *,* ]]
then
    ArchiveMode=true
    echo "BOD pure archive mode ${ArchiveMode}"
fi

# check for mandatory arguments source_objects and target have to be present if ArchiveMode is not set 
if [[ -z "${source_objects}" || -z "${target}" ]]; then
    # if not in pure archive mode exit script
    if [[ -z "${ArchiveMode}" ]]
    then
        echo "missing a required parameter (source_db -s and staging -t are required)" >&2
        exit 1
    fi
fi

# check if we have a valid target
if [[ ! ${targets} == *${target}* ]]; then
    echo "valid deploy targets are: '${targets}'" >&2
    exit 1
fi

# check db access
if [[ -z $(psql -lqt -h localhost) ]]; then
    echo "Unable to connect to database cluster" >&2
    exit 1
fi

# check source_objects
for source_object in "${array_source[@]}"; do
    array=(${source_object//./ })
    # check source objects
    if [ "${#array[@]}" -ne "3" -a "${#array[@]}" -ne "1" ]; then
        echo "table data sources have to be formatted like this: db.schema.table, database sources like this: db" >&2
        exit 1
    fi
    array=()
done

# check for lockfile, if there is one exit script, lock file is created by import_databases.sh
(ls ${lockfile} &> /dev/null) && { echo "lockfile found: ${lockfile} '$(cat ${lockfile})'" >&2; exit 1; }
attached_slaves=$(psql -qAt -h localhost -d postgres -c "select count(1) FROM pg_replication_slots where active=TRUE;")

# loop through source_object values
for source_object in "${array_source[@]}"; do
    array=(${source_object//./ })
    # tables go here
    if [ "${#array[@]}" -eq "3" ]; then
        echo "processing table ${source_object}..."
        source_db=${array[0]}
        source_schema=${array[1]}
        source_table=${array[2]}
        target_db="${source_db%_*}_${target}" # lubis_3d_master -> lubis_3d_$target
        target_schema="${source_schema}"
        target_table="${source_table}"
        source_id="${source_db}.${source_schema}.${source_table}"
        target_id="${target_db}.${target_schema}.${target_table}"
        array_target_table+=(${target_id})
        array_source_table+=(${source_object})
        array_target_combined+=(${target_id})
        check_table
        check_source
        copy_table
    fi
    # databases go here
    if [ "${#array[@]}" -eq "1" ]; then
        echo "processing database ${source_object}..."        
        source_db=${array[0]}
        target_db="${source_db%_*}_${target}"
        target_db_tmp="${target_db}_tmp_deploy"
        array_target_db+=(${target_db})
        array_source_db+=(${source_object})
        array_target_combined+=(${target_db})
        check_database
        check_source
        bod_create_archive
        copy_database        
    fi    
done

END=$(date +%s%3N)

# create new xlog position
$(psql -qAt -h localhost -d template1 -c "SELECT pg_switch_xlog();" > /dev/null)
# read new xlog position
MASTER_XLOG=$(psql -qAt -h localhost -d template1 -c "SELECT pg_current_xlog_location();")

echo "master has been updated in $(format_milliseconds $((END-START))) to xlog position: ${MASTER_XLOG}"
echo "waiting for ${attached_slaves} slaves to be pushed to xlog position ${MASTER_XLOG}..."

# wait for all slaves until they have replayed the new xlog
while :
do
    diff=999
    read slaves diff <<< $(psql \
    -X \
    -h localhost \
    -d postgres \
    --single-transaction \
    --set ON_ERROR_STOP=on \
    --no-align \
    -t \
    --field-separator ' ' \
    --quiet \
    -c "select count(1) as slaves, coalesce(sum(CASE WHEN diff >= 0 then diff ELSE NULL END)) as diff FROM ( SELECT pg_xlog_location_diff('${MASTER_XLOG}',replay_location) as diff from pg_stat_replication where state IN ('streaming')) sub;")

    if [[ ${diff} -eq 0  && ${slaves} -eq ${attached_slaves} ]]; then
        END_slaves=$(date +%s%3N)
        echo "${slaves} slaves have been updated in $(format_milliseconds $((END_slaves-END))) to xlog position: ${MASTER_XLOG}"
        break
    fi
done

# concatenate arrays for dml and ddl trigger
source_db=$(IFS=, ; echo "${array_source_db[*]}")
target_combined=$(IFS=, ; echo "${array_target_combined[*]}")

# fire dml trigger in sub shell
# redirect customized stdout and stderr to standard ones
if [[ -z "${ArchiveMode}" ]]
then
    (
    [[ ! ${target} == tile ]] && bash "${MY_DIR}/dml_trigger.sh" -s ${target_combined} -t ${target} 1>&5 2>&6
    )
    if [ "${#array_target_db[@]}" -gt "0" ]
    then
        # fire ddl trigger in sub shell
        # redirect customized stdout and stderr to standard ones    
        (
        [[ ! ${target} == tile ]] &&  bash "${MY_DIR}/ddl_trigger.sh" -s ${source_db} -t ${target} 1>&5 2>&6
        )   
    fi
fi

END_trigger=$(date +%s%3N)
echo "finished ${COMMAND} in $(format_milliseconds $((END_trigger-START)))"
