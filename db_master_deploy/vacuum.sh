#!/bin/bash
set -e
set -u
set -o pipefail

database=${1:-template1}
HOST_USER="-h pg-0.dev.bgdi.ch -U pgkogis"

PSQL() {
    psql -X ${HOST_USER} -d template1 "$@"
}

get_size_pretty() {
    local database=$1
    PSQL -At -c "SELECT pg_size_pretty(pg_database_size('${database}') );"
}

get_size() {
    local database=$1
    PSQL -At -c "SELECT pg_database_size('${database}');"
}

list_databases() {
    PSQL <<EOF
SELECT d.datname as Name,  pg_catalog.pg_get_userbyid(d.datdba) as Owner,
    CASE WHEN pg_catalog.has_database_privilege(d.datname, 'CONNECT')
        THEN pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(d.datname))
        ELSE 'No Access'
    END as Size
FROM pg_catalog.pg_database d
    order by
    1 asc,
    CASE WHEN pg_catalog.has_database_privilege(d.datname, 'CONNECT')
        THEN pg_catalog.pg_database_size(d.datname)
        ELSE NULL
    END desc -- nulls first
EOF
}

vacuum() {
    local database=$1
    echo "vacuum full analyze of database ${database}"
    size_before=$(get_size "${database}")
    size_before_pretty=$(get_size_pretty "${database}")
    start=$SECONDS
    vacuumdb -d "${database}" -f -q --skip-locked -F ${HOST_USER}
    size_after=$(get_size "${database}")
    size_after_pretty=$(get_size_pretty "${database}")
    diff=$(PSQL -At -c "SELECT pg_size_pretty(${size_after}::decimal-${size_before}::decimal);")
    echo "finished vacuum ${database} in $(( SECONDS - start ))s size: ${size_before_pretty} --> ${size_after_pretty} (${diff})"
}

[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

if [[ $database == "template1" ]]; then
    list_databases
else
    vacuum "${database}"
fi
