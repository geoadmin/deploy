#!/bin/bash
#
# script for bod review
# p.e.
# bod_master                            [ -d bod_master     ]
# bod_prod                              [ -d bod_prod       ]
#
# The script will do the following actions on the given database
# * json dump of the chsdi relevant views and columns
# * create or update an equally named branch in github
#
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
# root branch will be used as reference branch
root_branch="bod_master"
git_repo="git@github.com:geoadmin/db.git"
git_dir="$(pwd)/tmp"

# sql queries, must have a valid choice of attributes for all bod stagings
sql_layer_info="SELECT json_agg(row) FROM (SELECT bod_layer_id,topics,staging,bodsearch,download,chargeable FROM re3.view_bod_layer_info_de order by bod_layer_id asc) as row"
sql_catalog="SELECT json_agg(row) FROM (SELECT path,topic,category,bod_layer_id,selected_open,access,staging FROM re3.view_catalog order by bod_layer_id,bgdi_id asc) as row"
sql_layers_js="SELECT json_agg(row) FROM (SELECT * FROM re3.view_layers_js order by bod_layer_id asc) as row"
sql_wmtsgetcap="SELECT json_agg(row) FROM (SELECT fk_dataset_id,tile_matrix_set_id,format,timestamp,sswmts,zoomlevel_min,zoomlevel_max,topics,chargeable,staging FROM re3.view_bod_wmts_getcapabilities_de order by fk_dataset_id,format,timestamp asc) as row"
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
git checkout prod 1>/dev/null

git branch --merged | grep "bod_*" | xargs -r -n 1 git branch -d
git fetch --all --prune

generate_json() {
[ -d bod_review ] || mkdir bod_review

# json export
# re3.view_bod_layer_info_de
psql -h pg-0.dev.bgdi.ch -U www-data -d $1 -qAt -c "${sql_layer_info}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.view_bod_layer_info_de.json
# re3.view_catalog
psql -h pg-0.dev.bgdi.ch -U www-data -d $1 -qAt -c "${sql_catalog}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.view_catalog.json
# re3.view_layers_js
psql -h pg-0.dev.bgdi.ch -U www-data -d $1 -qAt -c "${sql_layers_js}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.view_layers_js.json
# re3.view_bod_wmts_getcapabilities_de
psql -h pg-0.dev.bgdi.ch -U www-data -d $1 -qAt -c "${sql_wmtsgetcap}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.view_bod_wmts_getcapabilities_de.json
# re3.topics
psql -h pg-0.dev.bgdi.ch -U www-data -d $1 -qAt -c "${sql_topics}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.topics.json    

git add .
# squash all commits to single commit
git reset $(git commit-tree HEAD^{tree} -m "squashed to single commit: ${COMMAND} by $(logname)") 
git push -f origin $1
} 

initialize_root_branch() {
echo "initializing ${root_branch} first..."
git checkout --orphan ${root_branch}
git rm . -rf 1>/dev/null
generate_json ${root_branch}
git checkout prod 1>/dev/null
}

# initialize root branch if it does not yet exists
# root branch will be the root/default branch
if [ ${branch_name} != "${root_branch}" ] && [ -z "$(git show-ref | grep -E "heads/${root_branch}$|origin/${root_branch}$")" ]; then
    initialize_root_branch
fi

# check if remote branch exists
if [[ "$(git show-ref | grep -E "heads/${branch_name}$|origin/${branch_name}$")" ]];then
    git checkout ${branch_name}
else
    if [[ "$(git show-ref | grep -E "heads/${root_branch}$|origin/${root_branch}$")" ]];then
        # create local branch referencing root branch
        git checkout -b ${branch_name} origin/${root_branch}
    else
        initialize_root_branch
        git checkout ${branch_name}
    fi
fi

# continue on error when trying to pull changes if remote does not exists
set +e
# overwrite local changes with remote version
git reset --hard origin/${branch_name} 2>/dev/null
set -e

generate_json ${bod_database}
