#!/bin/bash
#
# update sphinx index
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

SEARCH_GITHUB_BRANCH="develop-docker" # rename to master after migration to frankfurt
SEARCH_GITHUB_REPO="git@github.com:geoadmin/service-sphinxsearch.git"
SEARCH_GITHUB_FOLDER="${MY_DIR}/service-sphinxsearch"

display_usage() {
    echo -e "Usage:\\n$0 -t tables/databases -s staging"
    echo -e "\\t-s comma delimited list of tables and/or databases - mandatory"
    echo -e "\\t-t target staging - mandatory choose one of '${targets}'"
}

while getopts ":s:t:" options; do
    case "${options}" in
        t)
            target=${OPTARG}
            ;;
        s)
            tables=${OPTARG}
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

check_arguments() {
    # check for mandatory arguments
    if [[ -z "${target}" || -z "${tables}" ]]; then
        echo "missing a required parameter (source_db -s and taget_db -t are required)" >&2
        display_usage
        exit 1
    fi

    if [[ ! ${targets} == *${target}* ]]; then
        echo "valid deploy targets are: '${targets}'" >&2
        exit 1
    fi
}

initialize_git() {
    local folder repo branch
    folder=$1
    repo=$2
    branch=$3
    if [[ ! -d "${folder}" ]]; then
        git clone -b "${branch}" "${repo}" "${folder}"
    else
        # silently get latest changes from remote
        {
        pushd "${folder}"
        git checkout develop-docker
        git fetch
        git reset --hard origin/"${branch}"
        popd
        } &> /dev/null
    fi
}

update_sphinx() {
    # connect to sphinx instance and update sphinx indexes
    echo "Updating sphinx indexes on ${target} with db pattern ${tables}"
    initialize_git "${SEARCH_GITHUB_FOLDER}" "${SEARCH_GITHUB_REPO}" "${SEARCH_GITHUB_BRANCH}"
    # run docker command
    pushd "${SEARCH_GITHUB_FOLDER}"
    STAGING="${target}" DB="${tables}" make pg2sphinx
    popd
}

# source script until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0
# shellcheck source=./includes.sh
source "${MY_DIR}/includes.sh"
check_env

check_arguments

START_DML=$(date +%s%3N)
echo "start ${COMMAND}"
check_arguments
update_sphinx
END_DML=$(date +%s%3N)
echo "finished ${COMMAND} in $(format_milliseconds $((END_DML-START_DML)))"
