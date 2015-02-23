#!/bin/bash
MY_DIR=$(dirname $(readlink -f $0))
source "$MY_DIR/includes.sh"
USER_SCRIPT=$(whoami)

# pgkogis or replicator has to be allowed in the pg_hba.conf on the following instances
declare -A source
declare -A dbsuffix
source[prod]="10.220.6.23"
source[int]="10.220.4.94"
source[dev]="10.220.4.122"
source[master]="10.220.4.223"
dbsuffix[prod]="_prod"
dbsuffix[int]="_int"
dbsuffix[dev]="_dev"
dbsuffix[master]="_master"

LOOP_SQL=$(cat <<EOF
    SELECT datname FROM pg_database
    WHERE datistemplate = false and datname not in ('postgres') and datname in ('are') and datname not like '%_test' order by 1;
EOF
)

# run this script with postgres user
if [[ $USER_SCRIPT != "postgres" ]]; then 
    echo "This script must be run as postgres!" >&2 
    exit 1
fi 



# check for lockfile
(set -o noclobber; echo "$locktext" > "$lockfile"  2> /dev/null) || { echo "lockfile found: $lockfile '$(cat $lockfile)'" >&2; exit 1; }

trap 'rm -f "$lockfile"; echo "script aborted" >&2; exit $?' INT TERM EXIT

#for staging in prod int dev master
#for staging in dev master
echo "start importing databases"
for staging in master
do
    source=`eval echo "\${source[$staging]}"`
    suffix=`eval echo "\${dbsuffix[$staging]}"`
    psql -l -h $source -U pgkogis  &> /dev/null || { echo "$staging error connecting to $source ..."; continue; }
    for database in `psql -U pgkogis -h "$source" -t -c "$LOOP_SQL" -d template1`
    do
        DB_START=$(date +%s%3N)
        echo "$staging - importing database $database to $database$suffix from $source ($staging) ..."
        rm -rf "/tmp/$database$suffix/" &> /dev/null
        pg_dump -h $source -U pgkogis -o -Fd -f "/tmp/$database$suffix/" -j 8 $database
        psql -U pgkogis -h localhost -d template1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$database$suffix';" >/dev/null
        dropdb --if-exists "$database$suffix" &>/dev/null
        createdb "$database$suffix" &>/dev/null
        pg_restore -j 8 --no-owner -Fd -d $database$suffix "/tmp/$database$suffix/"  &>/dev/null
        ##pg_dump -h $source -U pgkogis -o -Fc $database | pg_restore  --no-owner -Fc -d $database$suffix
        DB_END=$(date +%s%3N)
        echo "$staging - db $database restored to $database$suffix in $((DB_END-DB_START)) miliseconds"
        echo "$staging - removing temporary files ..."
        rm -rf "/tmp/$database$suffix/" &> /dev/null
    done
done
echo "import finished"


rm -f "$lockfile"
trap - INT TERM EXIT
