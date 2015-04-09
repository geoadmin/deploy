#!/bin/bash
MY_DIR=$(dirname $(readlink -f $0))
source "$MY_DIR/includes.sh"

DUMPDIRECTORY="/home/geodata/db/"
TIMESTAMP=$(date +"%F %T")

display_usage() {
    echo -e "Usage:\n$0 -s source_database -t target_staging"
    echo -e "\t-s source database, comma delimited - mandatory"
    echo -e "\t-t target staging - mandatory choose one of '$targets' \n"
}

while getopts ":s:t:" options; do
    case "$options" in
        s)
            source_db=$OPTARG
            IFS=',' read -ra array_source <<< "$source_db"
            ;;
        t)
            target=$OPTARG
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

echo "start ${0##*/} $* (pid: $$)" 
START=$(date +%s%3N)

# check for mandatory arguments 
if [[ -z "$source_db" || -z "$target" ]];
then
    echo "missing a required parameter (source_db -s and staging -t are required)" >&2
    exit 1
fi

if [[ ! $targets == *$target* ]]
then
    echo "valid deploy targets are: '$targets'" >&2
    exit 1
fi

# check db access
if [[ -z `psql -lqt -h localhost -U pgkogis 2> /dev/null` ]]; then
    echo "Unable to connect to database" >&2
    exit 1
fi

# check if source database exists
for i in "${array_source[@]}"; do
    if [[ -z `psql -lqt -h localhost -U pgkogis | egrep "\b$i\b" 2> /dev/null` ]]; then
        echo "No existing databases are named $i." >&2
        exit 1
    fi
done

# demo target will not be versionized
if [[ $target == "demo" ]]
then
    echo "demo target will not be versionized in github"
    exit 0
fi

for db in "${array_source[@]}"
do
    db=${db%_*}                # remove db suffix lubis_3d_master -> lubis_3d
    target_db=$db"_"$target    # lubis_3d -> lubis_3d_dev
    dumpfile=$(printf "%s%s.sql" $DUMPDIRECTORY$target/ $db)
    echo "creating ddl dump $dumpfile of database $db in $target ..."
    pg_dump -U pgkogis -h localhost -s -O $target_db | sed -r '/^CREATE VIEW/ {n ;  s/,/\n      ,/g;s/FROM/\n    FROM/g;s/LEFT JOIN/\n    LEFT JOIN/g;s/WHERE/\n    WHERE\n       /g;s/GROUP BY/\n    GROUP BY\n       /g;s/SELECT/\n    SELECT\n       /g}' > $dumpfile
done

# update git
sudo su - geodata 2> /dev/null << HERE
    cd $DUMPDIRECTORY$target/
    git pull 2>&1
    echo "$TIMESTAMP | User: $USER | DB: $source_db | COMMAND: ${0##*/} $*" >> deploy.log
    # commit only if ddl of whole database has changed
    if git status --porcelain | grep -E "M|??" | grep ".sql$" > /dev/null; then
        git add .
        git commit -m "$TIMESTAMP | User: $USER | DB: $source_db | COMMAND: ${0##*/} $* auto commit of whole database deploy"
        git push origin $target
    fi
HERE

END=$(date +%s%3N)
echo "finished ${0##*/} $* in $(format_milliseconds $((END-START)))"
