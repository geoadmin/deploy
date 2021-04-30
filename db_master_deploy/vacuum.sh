#!/bin/bash
set -e
set -u
set -o pipefail

database=$1

PSQL() {
    psql -At -X -U pgkogis -h pg-0.dev.bgdi.ch -d "${database}" "$@"
}

get_size_pretty() {
    local database=$1
    PSQL -c "SELECT pg_size_pretty(pg_database_size('${database}') );"
}

get_size() {
    local database=$1
    PSQL -c "SELECT pg_database_size('${database}');"
}

vacuum() {
    echo "vacuum full analyze of database ${database}"
    size_before=$(get_size "${database}")
    size_before_pretty=$(get_size_pretty "${database}")
    start=$SECONDS
    vacuumdb -d "${database}" -f -q --skip-locked -F -h pg-0.dev.bgdi.ch -U pgkogis
    size_after=$(get_size "${database}")
    size_after_pretty=$(get_size_pretty "${database}")
    diff=$(PSQL -c "SELECT pg_size_pretty(${size_after}::decimal-${size_before}::decimal);")
    echo "finished vacuum ${database} in $(( SECONDS - start ))s size: ${size_before_pretty} --> ${size_after_pretty} (${diff})"
}

[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

vacuum
