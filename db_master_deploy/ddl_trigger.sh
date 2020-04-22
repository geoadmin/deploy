#!/bin/bash
#
# update github repository with database ddl dumps
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${MY_DIR}/includes.sh"
check_env

# DUMPDIRECTORY="/home/geodata/db/"
git_repo="git@github.com:geoadmin/db.git"
git_dir=$(mktemp -d -p "${MY_DIR}/tmp" "$(basename "$0")"_XXXXX)
trap "rm -rf ${git_dir}" EXIT HUP INT QUIT TERM STOP PWR

TIMESTAMP=$(date +"%F %T")

display_usage() {
    echo -e "Usage:\n$0 -s source_database -t target_staging"
    echo -e "\t-s source database, comma delimited - mandatory"
    echo -e "\t-t target staging - mandatory choose one of '${targets}' \n"
}

while getopts ":s:t:" options; do
    case "${options}" in
        s)
            source_db=${OPTARG}
            IFS=',' read -ra array_source <<< "${source_db}"
            ;;
        t)
            target=${OPTARG}
            ;;
        \? )
            display_usage
            exit 1
            ;;
        *)
            display_usage
            exit 1
            ;;
    esac
done


check_access() {
    # check for mandatory arguments 
    if [[ -z "${source_db}" || -z "${target}" ]]; then
        echo "missing a required parameter (source_db -s and staging -t are required)" >&2
        exit 1
    fi

    if [[ ! ${targets} == *${target}* ]]; then
        echo "valid deploy targets are: '${targets}'" >&2
        exit 1
    fi

    # check db access
    if [[ -z $(${PSQL} -lqt 2> /dev/null) ]]; then
        echo "Unable to connect to database" >&2
        exit 1
    fi

    # check if source database exists
    for i in "${array_source[@]}"; do
        if [[ -z $(${PSQL} -lqt | egrep "\b${i}\b" 2> /dev/null) ]]; then
            echo "No existing databases are named ${i}." >&2
            exit 1
        fi
    done

    # demo target will not be versionized
    if [[ ${target} == "demo" ]]; then
        echo "demo target will not be versionized in github"
        exit 0
    fi
}


process_dbs() {
    for db in "${array_source[@]}"
    do
        db=${db%_*}                # remove db suffix lubis_3d_master -> lubis_3d
        target_db="${db}_${target}"    # lubis_3d -> lubis_3d_dev
        # do not dump _test databases
        if [[ ${db} == *_test ]]; then
            echo "skip ddl trigger for database ${db} ..."
            continue
        fi
        dumpfile=$(printf "%s%s.sql" "${git_dir}/" "${db}")
        echo "creating ddl dump ${dumpfile} of database ${db} in ${target} ..."
        PG_DUMP -s -O ${target_db} | sed -r '/^CREATE VIEW/ {n ;  s/,/\n      ,/g;s/FROM/\n    FROM/g;s/LEFT JOIN/\n    LEFT JOIN/g;s/WHERE/\n    WHERE\n       /g;s/GROUP BY/\n    GROUP BY\n       /g;s/SELECT/\n    SELECT\n       /g}' > ${dumpfile}
    done
}


initialize_git() {
    git clone -b ${target} ${git_repo} ${git_dir}
}


update_git() {
    cd ${git_dir}
    echo "${TIMESTAMP} | User: ${USER} | DB: ${source_db} | COMMAND: ${COMMAND}" >> deploy.log
    # commit only if ddl of whole database has changed
    if git status --porcelain | grep -E "M|??" | grep ".sql$" > /dev/null; then
        git add .
        git commit -m "${TIMESTAMP} | User: ${USER} | DB: ${source_db} | COMMAND: ${COMMAND} auto commit of whole database deploy"
        git push origin ${target}
    fi
}

# source this file until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

echo "start ${COMMAND}" 
START_DDL=$(date +%s%3N)
check_access
initialize_git 2>&1
process_dbs
update_git 2>&1
END_DDL=$(date +%s%3N)
echo "finished ${COMMAND} in $(format_milliseconds $((END_DDL-START_DDL)))"
