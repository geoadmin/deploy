#!/bin/bash
#
# script for database and table managment on streaming replication master
# p.e.
# copy databases                        [ -s database   -t target   ]
# copy tables                           [ -s table      -t target   ]
# archive/snapshot bod                  [ -s bod_master -a 20150303 ]
set -e
MY_DIR=$(dirname $(readlink -f $0))

display_usage() {
    echo -e "Usage:\n$0 -d bod_database -b branch_name"
    echo -e "\t-d bod_database wich will be dumped as json"
    echo -e "\t-b name of the branch - Optional. Default value is -b bod_database value'\n"
}

while getopts ":d:b:" options; do
    case "${options}" in
        d)
            bod_database=${OPTARG}
            ;;
        b)
            branch_name=${OPTARG}
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

# default values
branch_name=${branch_name:-$bod_database}
git_repo="git@github.com:geoadmin/db.git"
git_dir="$(pwd)/tmp"
sql_layer_info="SELECT json_agg(row) FROM (SELECT bod_layer_id,topics,staging,bodsearch,download,chargeable FROM re3.view_bod_layer_info_de order by bod_layer_id asc) as row"
sql_catalog="SELECT json_agg(row) FROM (SELECT path,topic,category,bod_layer_id,selected_open,access,staging FROM re3.view_catalog order by path asc) as row"
sql_layers_js="SELECT json_agg(row) FROM (SELECT * FROM re3.view_layers_js order by bod_layer_id asc) as row"
sql_wmtsgetcap="SELECT json_agg(row) FROM (SELECT fk_dataset_id,tile_matrix_set_id,format,timestamp,sswmts,zoomlevel_min,zoomlevel_max,topics,chargeable,staging FROM re3.view_bod_wmts_getcapabilities_de order by fk_dataset_id asc) as row"
sql_topics="select json_agg(row) FROM (SELECT topic, order_key, default_background, selected_layers, background_layers,show_catalog, activated_layers, staging FROM re3.topics order by topic asc) as row"
COMMAND="${0##*/} $* (pid: $$)"

# check for mandatory arguments source_objects and target have to be present if ArchiveMode is not set 
if [[ -z "${bod_database}" ]]; then
    echo "missing a required parameter (bod_database -b is required)" >&2
    exit 1
fi

# check database connection
if [[ -z $(psql -lqt -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database}) ]]; then
    echo "something went wrong when trying to connect to ${bod_database} on pg-0.dev.bgdi.ch" >&2
    echo "please make sure that PGPASS and PGUSER Variables are set and the database name ${bod_database} is written correctly" >&2
    exit 1
fi

# check json queries
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "EXPLAIN ${sql_layer_info}" 1>/dev/null
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "EXPLAIN ${sql_catalog}" 1>/dev/null
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "EXPLAIN ${sql_layers_js}" 1>/dev/null
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "EXPLAIN ${sql_wmtsgetcap}" 1>/dev/null
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "EXPLAIN ${sql_topics}" 1>/dev/null

# create temporary git folder from scratch and checkout
mkdir -p ${git_dir}
cd "${git_dir}"
if [ ! -d "${git_dir}/db/.git" ]
then
    git clone ${git_repo}
fi

cd "${git_dir}/db"

# checkout default branch
git checkout prod

# remove local branches bod_* which are not present on remote
git branch --merged | grep "bod_*" | xargs -n 1 git branch -d

git checkout -B ${branch_name} 
# continue on error when trying to pull changes if remote does not exists
set +e
git pull 2> /dev/null
set -e
[ -d bod_review ] || mkdir bod_review

# json export
# re3.view_bod_layer_info_de
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "${sql_layer_info}" | python -m json.tool > bod_review/re3.view_bod_layer_info_de.json
# re3.view_catalog
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "${sql_catalog}" | python -m json.tool > bod_review/re3.view_catalog.json
# re3.view_layers_js
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "${sql_layers_js}" | python -m json.tool > bod_review/re3.view_layers_js.json
# re3.view_bod_wmts_getcapabilities_de
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "${sql_wmtsgetcap}" | python -m json.tool > bod_review/re3.view_bod_wmts_getcapabilities_de.json
# re3.topics
psql -h pg-0.dev.bgdi.ch -U www-data -d ${bod_database} -qAt -c "${sql_topics}" | python -m json.tool > bod_review/re3.topics.json

git add .
git commit -m "${COMMAND} by $(logname)"
git push -f origin ${branch_name}
