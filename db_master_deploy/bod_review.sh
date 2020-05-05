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
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

display_usage() {
    echo -e "Usage:\n$0 -d bod_database -t tag_name"
    echo -e "\t-d bod_database wich will be dumped as json"
    echo -e "\t-t name of the tag - Optional. Default value is -t bod_database value'\n"
}

while getopts ":d:t:" options; do
    case "${options}" in
        d)
            bod_database=${OPTARG}
            ;;
        t)
            tag_name=${OPTARG}
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
tag_name="tag_${tag_name:-$bod_database}"
# root branch will be used as reference branch
root_branch="bod_review"
git_repo="git@github.com:geoadmin/db.git"
git_dir=$(mkdir -p "${MY_DIR}/tmp" && mktemp -d -p "${MY_DIR}/tmp"  "$(basename "$0")"_XXXXX)

trap "rm -rf ${git_dir}" EXIT HUP INT QUIT TERM STOP PWR

# sql queries, must have a valid choice of attributes for all bod stagings
sql_layer_info="SELECT json_agg(row) FROM (SELECT bod_layer_id,topics,staging,bodsearch,download,chargeable FROM re3.view_bod_layer_info_de order by bod_layer_id asc) as row"
sql_catalog="SELECT json_agg(row) FROM (SELECT distinct topic,bod_layer_id,selected_open,staging FROM re3.view_catalog where bod_layer_id > '' order by 1,2 ) as row"
sql_layers_js="SELECT layer_id,row_to_json(t) as json FROM  (SELECT * FROM re3.view_layers_js order by layer_id asc) t"
sql_wmtsgetcap="SELECT json_agg(row) FROM (SELECT fk_dataset_id,format,timestamp,resolution_min,resolution_max,topics,chargeable,staging FROM re3.view_bod_wmts_getcapabilities_de order by fk_dataset_id,format,timestamp asc) as row"
sql_topics="select json_agg(row) FROM (SELECT topic, default_background, selected_layers, background_layers,show_catalog, activated_layers, staging FROM re3.topics order by topic asc) as row"

COMMAND="${0##*/} $* (pid: $$)"

check_access() {
    # check env from includes.sh
    check_env

    # check for mandatory arguments source_objects and target have to be present if ArchiveMode is not set
    if [[ -z "${bod_database}" ]]; then
        echo "missing a required parameter (bod_database -b is required)" >&2
        exit 1
    fi

    # check database connection
    if [[ -z $(PSQL -lqt -U www-data -d "${bod_database}") ]]; then
        echo "something went wrong when trying to connect to ${bod_database} on pg-0.dev.bgdi.ch" >&2
        echo "please make sure that PGPASS and PGUSER Variables are set and the database name ${bod_database} is written correctly" >&2
        exit 1
    fi

    # check json queries
    PSQL -U www-data -d "${bod_database}" -qAt -c "EXPLAIN ${sql_layer_info}" 1>/dev/null
    PSQL -U www-data -d "${bod_database}" -qAt -c "EXPLAIN ${sql_catalog}" 1>/dev/null
    PSQL -U www-data -d "${bod_database}" -qAt -c "EXPLAIN ${sql_layers_js}" 1>/dev/null
    PSQL -U www-data -d "${bod_database}" -qAt -c "EXPLAIN ${sql_wmtsgetcap}" 1>/dev/null
    PSQL -U www-data -d "${bod_database}" -qAt -c "EXPLAIN ${sql_topics}" 1>/dev/null
}

initialize_git() {
    # create temporary git folder from scratch and checkout
    git clone ${git_repo} "${git_dir}" && cd "${git_dir}"

    # checkout default branch
    git checkout prod 1>/dev/null
    git branch --merged | grep "bod_*" | xargs -r -n 1 git branch -d || :
    git fetch --all --prune

    # initialize root branch if it does not yet exists
    # root branch will be the root/default branch
    if ! git show-ref | grep -qE "heads/${root_branch}$|origin/${root_branch}$"; then
        echo "initializing ${root_branch} first..."
        git checkout --orphan ${root_branch}
        git rm . -rf 1>/dev/null
    fi

    # switch branch if necessary
    if [ "$(git symbolic-ref -q --short HEAD)" != "${root_branch}" ]; then
        git checkout ${root_branch}
    fi
}

generate_json() {
    [ -d bod_review ] || mkdir bod_review
    [ -d bod_review/re3.view_layers_js ] || mkdir bod_review/re3.view_layers_js

    # json export
    # re3.view_bod_layer_info_de
    PSQL -U www-data -d "$1" -qAt -c "${sql_layer_info}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.view_bod_layer_info_de.json
    # re3.view_catalog
    PSQL -U www-data -d "$1" -qAt -c "${sql_catalog}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.view_catalog.json
    # re3.view_layers_js
    rm bod_review/re3.view_layers_js/*.json -rf
    PSQL -U www-data -d "$1" -qAt -F ' ' -c "${sql_layers_js}" | while read -a Record; do
        echo "${Record[1]}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.view_layers_js/"${Record[0]}".json
    done

    # re3.view_bod_wmts_getcapabilities_de
    PSQL -U www-data -d "$1" -qAt -c "${sql_wmtsgetcap}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.view_bod_wmts_getcapabilities_de.json
    # re3.topics
    PSQL -U www-data -d "$1" -qAt -c "${sql_topics}" | python -m json.tool | sed 's/ *$//' > bod_review/re3.topics.json

    set +e
    git add .
    git commit -m "${COMMAND} tag: ${tag_name} by $(whoami)"
    git tag "${tag_name}" -f
    git push origin ${root_branch} --tags -f 2>&1
    set -e
}

# source this file until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0
source "${MY_DIR}/includes.sh"

check_access
initialize_git 2>&1
generate_json "${bod_database}"
