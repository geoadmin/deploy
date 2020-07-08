#!/bin/bash
#
# script for database and table managment on streaming replication master
# p.e.
# copy databases                        [ -s database   -t target   ]
# copy tables                           [ -s table      -t target   ]
# archive/snapshot bod                  [ -s bod_master -a 20150303 ]

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
display_usage() {
    echo -e "Usage:\n$0 -s source_objects -t target_staging -a timestamp for BOD snapshot/archive (YYYYMMDD)"
    echo -e "\t-s comma delimited list of source databases and/or tables - mandatory"
    echo -e "\t-t target staging - mandatory choose one of 'dev int prod demo tile'"
    echo -e "\t-r refresh materialized views true|false - Optional, default: true'"
    echo -e "\t-d refresh sphinx indexes true|false - Optional, default: true'"
    echo -e "\t-a is optional and only valid for BOD, if you dont enter a target the script will just create an archive/snapshot copy of the bod\n"
}

while getopts ":s:t:a:m:r:d:" options; do
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
        m)
            export message=${OPTARG}
            ;;
        r)
            refreshmatviews=${OPTARG}
            ;;
        d)
            refreshsphinx=${OPTARG}
            ;;
        *)
            display_usage
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
    check_table_source() {
        set +o pipefail
        # check if source table exists, views cannot be deployed
        if ! PSQL -qAt -c "SELECT table_catalog||'.'||table_schema||'.'||table_name FROM information_schema.tables where lower(table_type) not like 'view'" -d "${source_db}" 2> /dev/null | egrep -q "\b${source_id}\b"; then
            echo "source table does not exist ${source_id} " >&2
            exit 1
        fi
        set -o pipefail
    }

    check_table_target() {
        # check if target table exists
        set +o pipefail
        if ! PSQL -qAt -c "SELECT table_catalog||'.'||table_schema||'.'||table_name FROM information_schema.tables where lower(table_type) not like 'view'" -d "${target_db}" 2> /dev/null | egrep -q "\b${target_id}\b"; then
            echo "target table does not exist ${target_id}." >&2
            exit 1
        fi
        set -o pipefail
    }

    check_table_schema() {
        # check if source and target table have the same structure (column name and data type)
        source_columns=$(PSQL -d "${source_db}" -Atc "select column_name,data_type FROM information_schema.columns WHERE table_schema = '${source_schema}' AND table_name = '${source_table}' order by 1;")
        columns=$(PSQL -d "${source_db}" -Atc "select column_name FROM information_schema.columns WHERE table_schema = '${source_schema}' AND table_name = '${source_table}';" | xargs | sed -e 's/ /,/g') # comma separted list of all attributes for order independent copy command
        target_columns=$(PSQL -d "${target_db}" -Atc "select column_name,data_type FROM information_schema.columns WHERE table_schema = '${target_schema}' AND table_name = '${target_table}' order by 1;")
        if [ ! "${source_columns}" == "${target_columns}" ]; then
            {
            echo "structure of source and target table is different."
            sleep 1; echo "debug output"
            printf "%-69s %-70s\n" "${source_db}.${source_schema}.${source_table}" "${target_db}.${target_schema}.${target_table}"
            printf '%140s\n' | tr ' ' -
            pr -w 140 -m -t <( echo "${source_columns}" ) <( echo "${target_columns}" )
            diff <( echo "${source_columns}" ) <( echo "${target_columns}" ) | colordiff
            } >&2
            exit 1
        fi
    }

    check_table_dependencies() {
        # get count of referencing tables/constraints, skip table if it is referenced by other tables
        referencing_tables_sql="
        SELECT count(1)
            FROM pg_catalog.pg_constraint r
            WHERE  r.contype = 'f'
            AND conrelid::regclass != confrelid::regclass
            AND confrelid::regclass = '${source_schema}.${source_table}'::regclass;
        "
        referencing_tables=$(PSQL -qAt -d "${source_db}" -c "${referencing_tables_sql}")
        if [ "${referencing_tables}" -gt 0 ]; then
            echo "cannot copy table ${source_id}, table is referenced by ${referencing_tables} objects, use db_copy instead." >&2
            return 1
        fi
    }
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
    set +o pipefail
    if ! PSQL -lqt 2> /dev/null | egrep -q "\b${source_db}\b"; then
        echo "No existing databases are named ${source_db}." >&2
        exit 1
    fi
    set -o pipefail
}

#######################################
# update materialized views in current databases
# Globals:
#   source_db
#   source_schema
#   source_table
#   target_db
#   target_schema
#   target_table
# Arguments:
#   $1: table_scan | table_commit | database
# Returns:
#   None
#######################################
update_materialized_views() {
    if [[ "${refreshmatviews}" =~ ^true$ ]]; then
        if [ "$1" == "table_scan" ]; then
            for matview in $(PSQL  -qAt -c "Select CASE WHEN strpos(view_name,'.')=0 THEN concat('public.',view_name) ELSE view_name END as view_name from _bgdi_analyzetable('${target_schema}.${target_table}') where relkind = 'm';" -d "${target_db}" 2> /dev/null); do
                echo "table_scan: found materialized view ${target_db}.${matview} which is referencing ${target_schema}.${target_table} ..."
                array_matviews+=("${target_db}.${matview}")
            done
        elif [ "$1" == "table_commit" ]; then
            for matview in "${array_matviews[@]}"; do
                target_db=$(echo $matview | cut -d '.' -f 1)
                matview=$(echo $matview | cut -d '.' -f 1 --complement)
                PSQL -d template1 -c "alter database ${target_db} SET default_transaction_read_only = off;" >/dev/null
                echo "table_commit: updating materialized view ${matview} ..."
                PGOPTIONS='--client-min-messages=warning' PSQL -qAt -c "Select _bgdi_refreshmaterializedviews('${matview}'::regclass::text);" -d "${target_db}" >/dev/null
                array_target_combined+=("${target_db}.${matview}")
                PSQL -d template1 -c "alter database ${target_db} SET default_transaction_read_only = on;" >/dev/null
            done
        elif [ "$1" == "database" ]; then
            for matview in $(PSQL -qAt -c "Select _bgdi_showmaterializedviews();" -d "${source_db}" 2> /dev/null); do
                echo "database: updating materialized view ${source_db}.${matview} before starting deploy ..."
                PGOPTIONS='--client-min-messages=warning' PSQL -qAt -c "Select _bgdi_refreshmaterializedviews('${matview}'::regclass::text);" -d "${source_db}" >/dev/null
            done
        fi
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
        if [[ ${#timestamp} -gt 0 ]]; then
            if [[ ! ${timestamp} =~ (^[a-zA-Z0-9]+$)  ]]; then
                echo "timestamp must match the pattern [a-zA-Z0-9]+"  >&2
                exit 1
            fi
            archive_bod="${source_db}${timestamp}"
            echo "Archiving ${source_db} as ${archive_bod}..."
            PSQL -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${archive_bod}';" >/dev/null
            DROPDB --if-exists "${archive_bod}" &> /dev/null
            PSQL -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${source_db}';" >/dev/null
            CREATEDB -O postgres --encoding 'UTF-8' -T "${source_db}" "${archive_bod}" >/dev/null
            PSQL -d template1 -c "COMMENT ON DATABASE ${archive_bod} IS 'snapshot/archive copy from ${source_db} on $(date '+%F %T') with command ${COMMAND} by user ${USER}';" > /dev/null
            echo "bash bod_review.sh -d ${archive_bod} ..."
            bash "${MY_DIR}/bod_review.sh" -d "${archive_bod}"
            if [[ ! -z "${ArchiveMode}" ]]; then
                # skip rest of loop if we are in pure archive mode (bod-only)
                return 1
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

    #check if master is the source and, if not, ask for confirmation but only once
    if [[ ! ${source_db} == *_master ]]; then
        echo -n "Master is not the selected source. Do you want to continue? (y/n)"
        echo
        [ "${answer+x}" ] || read answer
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
    size=$(PSQL -qAt -d "${source_db}" -c "SELECT pg_size_pretty(pg_database_size('"${source_db}"'));")
    echo "copy ${source_db} to ${target_db} size: ${size} attached slaves: ${attached_slaves}"
    echo "creating temporary database ${target_db_tmp} ..."
    PSQL -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${target_db_tmp}';" >/dev/null
    DROPDB --if-exists "${target_db_tmp}" &> /dev/null
    PSQL -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${source_db}';" >/dev/null

    # toposhop db's have to be created with owner swisstopo
    if [[ -z "${ToposhopMode}" ]]; then
        CREATEDB -O postgres --encoding 'UTF-8' -T "${source_db}" "${target_db_tmp}" >/dev/null
    else
        CREATEDB -O swisstopo --encoding 'UTF-8' -T "${source_db}" "${target_db_tmp}" >/dev/null
    fi

    echo "replacing ${target_db} with ${target_db_tmp} ..."
    PSQL -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${target_db}';" >/dev/null
    DROPDB --if-exists "${target_db}" &>/dev/null
    PSQL -d template1 -c "alter database ${target_db_tmp} rename to ${target_db};" >/dev/null

    # add some metainformation to the copied database as comment
    PSQL -d template1 -c "COMMENT ON DATABASE ${target_db} IS 'copied from ${source_db} on $(date '+%F %T') with command ${COMMAND} by user ${USER}';" > /dev/null

    # set database to read-only if it is not a _master or _demo database and if not toposhop reverse deploy and if not diemo database
    REGEX="^(master|demo)$"
    REGEX_DIEMO="^diemo_(master|dev|int|prod)$"
    if [[ ! ${target} =~ ${REGEX} && -z "${ToposhopMode}" && ! ${target_db} =~ ${REGEX_DIEMO} ]]; then
        PSQL -d template1 -c "alter database ${target_db} SET default_transaction_read_only = on;" >/dev/null
    else
        PSQL -d template1 -c "alter database ${target_db} SET default_transaction_read_only = off;" >/dev/null
    fi

    # toposhop_(master|dev|int) have a max number of connections of 15
    REGEX="^toposhop_(master|dev|int)$"
    [[ ${target_db} =~ ${REGEX} ]] && PSQL -d template1 -c "ALTER DATABASE ${target_db} WITH CONNECTION LIMIT 15;" >/dev/null

    REGEX="^bod_"
    if [[ ${source_db} =~ ${REGEX} ]]; then
        echo "bash bod_review.sh -d ${source_db} ..."
        bash "${MY_DIR}/bod_review.sh" -d "${source_db}"
        echo "bash bod_review.sh -d ${target_db} ..."
        bash "${MY_DIR}/bod_review.sh" -d "${target_db}"
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
    PSQL -d template1 -c "alter database ${target_db} SET default_transaction_read_only = off;" >/dev/null
    # get primary keys for table sorting
    primary_keys_sql="SELECT string_agg(a.attname,', ')
    FROM   pg_index i
    JOIN   pg_attribute a ON a.attrelid = i.indrelid
                         AND a.attnum = ANY(i.indkey)
    WHERE  i.indrelid = '${source_schema}.${source_table}'::regclass
    AND    (i.indisprimary OR i.indisunique);
    "
    primary_keys=$(PSQL -qAt -d "${source_db}" -c "${primary_keys_sql}")

    jobs=${CPUS}
    rows=$(PSQL -qAt -d "${source_db}" -c "SELECT count(1) FROM ${source_schema}.${source_table};")
    size=$(PSQL -qAt -d "${source_db}" -c "SELECT pg_size_pretty(pg_total_relation_size('"${source_schema}.${source_table}"'));")
    increment=$( Ceiling "${rows}" "${jobs}" )
    # no multithreading if less than 1000 rows
    if [ "${rows}" -lt 1000 ]; then
        jobs=1
        increment=${rows}
    fi
    echo "multithread copy ${source_id} to ${target_id} rows: ${rows} threads: ${jobs} rows/thread: ${increment} size: ${size} attached slaves: ${attached_slaves}"

    echo "drop indexes on ${target_id}"
    set +o pipefail
    ( PG_DUMP --if-exists -c -t "${source_schema}.${source_table}" -s "${source_db}" 2>/dev/null | egrep "\bDROP INDEX\b" | PSQL -d "${target_db}"  2>/dev/null ) || true
    set -o pipefail

    # populate array with foreign key constraints on target table
    declare -A foreign_keys=( )
    while IFS=$'\|' read -a Record; do
        foreign_keys["${Record[0]}"]="${Record[1]}"
    done < <(
    PSQL --quiet --no-align  -t -c "
    SELECT conname,
        pg_catalog.pg_get_constraintdef(r.oid, true) as condef
    FROM pg_catalog.pg_constraint r
    WHERE r.conrelid = '${target_schema}.${target_table}'::regclass AND r.contype = 'f' ORDER BY 1;" "${target_db}" 2>/dev/null
    )

    if [ "${#foreign_keys[@]}" -gt 0 ]; then
        for i in "${!foreign_keys[@]}"
        do
            echo "DROP FOREIGN KEY CONSTRAINT ${i} FROM ${target_id} ..."
            echo "ALTER TABLE IF EXISTS ONLY ${target_schema}.${target_table} DROP CONSTRAINT IF EXISTS ${i};" | PSQL  -d "${target_db}" &> /dev/null
        done
    fi

    echo "truncate table ${target_id}"
    ( PSQL -c "begin; TRUNCATE TABLE ${target_schema}.${target_table}; commit;" -d "${target_db}" )

    (
    local pids=()
    for ((i=1; i<=jobs; i++)); do
        offset=$(echo "((${i}-1)*${increment})" | bc)
        if [ $((offset+increment)) -gt "${rows}" ]; then counter=${rows}; else counter=$((offset+increment));fi
        echo "dumping ${offset}..${counter}"
        ( PSQL -qAt -d "${source_db}" -c "COPY ( SELECT ${columns} FROM ${source_schema}.${source_table} order by ${primary_keys:=1} asc offset ${offset} limit ${increment} ) TO STDOUT with csv" | PSQL -qAt -d "${target_db}" -c "SET session_replication_role = replica; COPY ${target_schema}.${target_table} (${columns}) from stdin with csv; SET session_replication_role = DEFAULT;" )& pids+=("$!")
    done;
    wait "${pids[@]}" 2> /dev/null
    )

    echo "create indexes on ${target_id}"
    set +o pipefail
    ( PG_DUMP --if-exists -c -t "${source_schema}.${source_table}" -s "${source_db}" 2>/dev/null | egrep -i "\bcreate\b" | egrep -i "\bindex\b" | sed "s/^/set search_path = ${source_schema}, public, pg_catalog; /" | sed "s/'/\\\'/g" | xargs --max-procs=${jobs} -I '{}' sh -c 'psql -X -h localhost -d $@ -c "{}"' -- "${target_db}" ) || true
    set -o pipefail

    if [ "${#foreign_keys[@]}" -gt 0 ]; then
        for i in "${!foreign_keys[@]}"
        do
            echo "CREATE FOREIGN KEY CONSTRAINT ${i} ON ${target_id} ..."
            echo "ALTER TABLE ONLY ${target_schema}.${target_table} ADD CONSTRAINT ${i} ${foreign_keys[${i}]};" | PSQL  -d "${target_db}" &> /dev/null
        done
    fi
    # update materialized views in target database after table copy
    update_materialized_views table_scan

    # set database to read-only if it is not a _master or _demo database or a diemo database
    REGEX="^(master|demo)$"
    REGEX_DIEMO="^diemo_(master|dev|int|prod)$"
    if [[ ! ${target} =~ ${REGEX} && -z "${ToposhopMode}" && ! ${target_db} =~ ${REGEX_DIEMO} ]]; then
        PSQL  -d template1 -c "alter database ${target_db} SET default_transaction_read_only = on;" >/dev/null
    fi
}


#######################################
# write lock
# Globals:
#   array_source
#   LOCK_DIR
#   LOCK_FD
#   USER
#   target
# Arguments:
#   None
# Returns:
#   None
#######################################
write_lock() {
    local timeout=3600  # max retry interval in seconds
    local counter=0
    local increment=5   # check every n seconds
    local status=0
    # create unique array of db targets
    local uniq_db_target=($(
    for source in "${array_source[@]}"; do
        array=(${source//./ })
        echo "${array[0]%_*}_${target:-${timestamp}}"
    done | sort | uniq
    ))

    until [ "${counter}" -gt "${timeout}" ]
    do
        status=0
        for index in "${!uniq_db_target[@]}"; do
            target_db=${uniq_db_target[${index}]}
            # we need a differend fd for each database, we are using numbers from 500 upwards for these fds
            fd=$((500+index))
            lock ${target_db} ${fd} || { status=1; echo "target db ${target_db} is locked, waiting for deploy process to finish (${counter}/${timeout}) ..."; }
        done

        # break the until loop if all the databases have been locked succesfully
        [ ${status} -eq 0 ] && break
        sleep ${increment}
        (( counter += increment ))
    done
    [[ ${status} -eq 1 ]] && { >&2 echo "one of the target dbs is blocked by another deploy script. retry to deploy later with this command: ${COMMAND}."; exit 1; } || return 0
}


#######################################
# lock
# source: http://kfirlavi.herokuapp.com/blog/2012/11/06/elegant-locking-of-bash-program/
# Globals:
#   LOCK_DIR
#   LOCK_FD
# Arguments:
#   prefix
#   fd
# Returns:
#   0 || 1
#######################################
lock() {
    local prefix=$1
    local fd=${2:-$LOCK_FD}
    local lock_file=$LOCK_DIR/$prefix.lock

    # create lock file
    eval "exec $fd>$lock_file"
    # acquier the lock
    flock -n "$fd" && return 0 || return 1
}


#######################################
# check if toposhop deploy
# Globals:
#   target
# Arguments:
#   source_db
# Returns:
#   ToposhopMode (true|unset)
#######################################
check_toposhop() {
    local source_db=$1
    # check if toposhop deploy toposhop_prod -> toposhop_dev or toposhop_prod -> toposhop_int
    if [[ "${source_db}" =~ ^toposhop_prod$ ]]; then
        # check deploy targets, only dev and int target is allowed
        if [[ ! ${targets_toposhop} =~ ${target} ]]; then
            echo "valid toposhop deploy targets are: '${targets_toposhop}'" >&2
            exit 1
        fi
        ToposhopMode=true
    else
        # check if we have a valid standard deploy target
        if [[ ! ${targets} =~ ${target} ]]; then
            echo "valid standard deploy targets are: '${targets}'" >&2
            exit 1
        fi
        unset ${ToposhopMode} &> /dev/null || :
    fi
}


#######################################
# check input paramaters
# Globals:
#   target
#   source_objects
#   timestamp
#   ArchiveMode
#   refreshmatviews
#   refreshsphinx
#   array_source
# Arguments:
#   None
# Returns:
#   None
#######################################
check_input() {
# if source_object is bod and target is empty and timestamp is present and source_object does not contain any ","
if [[ ${source_objects%_*} == bod && -z "${target}" && ! -z "${timestamp}" && ! "${source_objects}" = *,* ]]
then
    ArchiveMode=true
    echo "BOD pure archive mode ${ArchiveMode}"
fi

# check for mandatory arguments source_objects and target have to be present if ArchiveMode is not set
if [[ -z "${source_objects}" || -z "${target}" ]]; then
    # if not in pure archive mode exit script
    if [[ -z "${ArchiveMode}" ]]; then
        echo "missing a required parameter (source_db -s and staging -t are required)" >&2
        exit 1
    fi
fi

# check if refresh materialized view switch is either true or false
if [[ ! "${refreshmatviews}" =~ ^(true|false)$ ]]; then
    echo "wrong parameter -r ${refreshmatviews} , should be true or false" >&2
    exit 1
fi

# check if sphinx index switch is either true or false
if [[ ! "${refreshsphinx}" =~ ^(true|false)$ ]]; then
    echo "wrong parameter -r ${refreshsphinx} , should be true or false" >&2
    exit 1
fi

# check db access
if [[ -z $(PSQL -lqt ) ]]; then
    echo "Unable to connect to database cluster" >&2
    exit 1
fi

# check source_objects
for source_object in "${array_source[@]}"; do
    local array=(${source_object//./ })
    # check source objects
    if [ "${#array[@]}" -ne "3" -a "${#array[@]}" -ne "1" ]; then
        echo "table data sources have to be formatted like this: db.schema.table, database sources like this: db" >&2
        exit 1
    fi
done
}

[ "$0" = "${BASH_SOURCE[*]}" ] || return 0
source "${MY_DIR}/includes.sh"
# check environment and load settings from includes.sh
check_env

# global and default values
refreshmatviews=${refreshmatviews:-true}
refreshsphinx=${refreshsphinx:-true}

CPUS=$(grep -c "processor" < /proc/cpuinfo) || CPUS=1
START=$(date +%s%3N)

echo "start ${COMMAND}"
check_input
# start loop and stop the script if db target is blocked by another db deploy
write_lock

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
        check_toposhop ${source_db}
        check_table # load check_table functions
            check_table_source # abort script if source table does not exist
            check_table_target # abort script if target table does not exist
            check_table_schema # abort script if source and target schema are not identical
            check_table_dependencies || continue # continue script if table has dependencies
        check_source
        copy_table
    fi
    # databases go here
    if [ "${#array[@]}" -eq "1" ]; then
        echo "processing database ${source_object}..."
        source_db=${array[0]}
        # if we have a bod ArchiveMode Deploy target is empty, create a lock file with the timestamp as suffix instead of deploy target
        target_db="${source_db%_*}_${target:-${timestamp}}"
        target_db_tmp="${target_db}_tmp_deploy"
        array_target_db+=(${target_db})
        array_source_db+=(${source_object})
        array_target_combined+=(${target_db})
        check_toposhop ${source_db}
        check_database
        check_source
        update_materialized_views database
        bod_create_archive || continue
        copy_database
    fi
done

END=$(date +%s%3N)

# create a distinct list of matviews and update matviews
if [ "${#array_matviews[@]}" -gt "0" ]; then
    array_matviews=($(printf "%s\n" "${array_matviews[@]}" | sort -u));
    update_materialized_views table_commit
fi

# create new xlog position
PSQL -qAt -d template1 -c "SELECT pg_switch_xlog();" > /dev/null
# read new xlog position
MASTER_XLOG=$(PSQL -qAt -d template1 -c "SELECT pg_current_xlog_location();")

echo "master has been updated in $(format_milliseconds $((END-START))) to xlog position: ${MASTER_XLOG}"

# concatenate arrays for dml and ddl trigger
source_db=$(IFS=, ; echo "${array_source_db[*]}")
target_combined=$(IFS=, ; echo "${array_target_combined[*]}")

# fire dml and ddl trigger in sub shell if not in ArchiveMode or ToposhopDeploy Mode
# redirect customized stdout and stderr to standard ones
if [[ -z "${ArchiveMode}" && -z "${ToposhopMode}" ]]; then
    (
    [[ ! ${target} == tile && "${refreshsphinx}" =~ ^true$ ]] && bash "${MY_DIR}/dml_trigger.sh" -s "${target_combined}" -t "${target}"
    )
    if [ "${#array_target_db[@]}" -gt "0" ]
    then
        # fire ddl trigger in sub shell
        # redirect customized stdout and stderr to standard ones
        (
        [[ ! ${target} == tile ]] &&  bash "${MY_DIR}/ddl_trigger.sh" -s "${source_db}" -t "${target}"
        )
    fi
fi

END_trigger=$(date +%s%3N)
echo "finished ${COMMAND} in $(format_milliseconds $((END_trigger-START)))"
