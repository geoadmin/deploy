#!/bin/bash
#
# update sphinx index

MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# shpinxsearch makefile
SEARCH_GITHUB_BRANCH="master"
SEARCH_GITHUB_REPO="git@github.com:geoadmin/service-sphinxsearch.git"
SEARCH_GITHUB_FOLDER="/data/geodata/automata/service-sphinxsearch"

# sphinxsearch published versions
VHOST_GITHUB_BRANCH="master"
VHOST_GITHUB_REPO="git@github.com:geoadmin/infra-vhost.git"
VHOST_GITHUB_FOLDER="/data/geodata/automata/infra-vhost"

# global variable set by get_sphinx_image_tag function
SPHINX_IMAGE_TAG=""

display_usage() {
    echo -e "Usage:\\n$0 -t tables/databases -s staging"
    echo -e "\\t-s comma delimited list of tables and/or databases - mandatory"
    # shellcheck disable=SC2154
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
    ########################################
    # check if the repo is checked out in the folder
    # if not check it out and switch to the branch
    ########################################
    local folder repo branch
    folder=$1
    repo=$2
    branch=$3
    if [[ ! -d "${folder}" ]]; then
        git clone -b "${branch}" "${repo}" "${folder}"
    else
        # silently get latest changes from remote
        {
            pushd "${folder}" || exit
            git fetch
            git checkout "${branch}"
            git reset --hard origin/"${branch}"
            popd || exit
        } &> /dev/null
    fi
}

get_sphinx_image_tag() {
    ########################################
    # gets the sphinx image tag from the infra-vhost repo for the given staging
    # and saves the tag in the global variable SPHINX_IMAGE_TAG
    ########################################
    local staging=$1
    initialize_git "${VHOST_GITHUB_FOLDER}" "${VHOST_GITHUB_REPO}" "${VHOST_GITHUB_BRANCH}" || :

    if image_tag=$(grep SERVICE_SEARCH_SPHINX_DOCKER_IMAGE_TAG "${VHOST_GITHUB_FOLDER}/systems/api3/service-search/${staging}/${staging}.env"); then
        mapfile -td = fields < <(printf "%s\\0" "${image_tag}")
        SPHINX_IMAGE_TAG="${fields[1]}"
    else
        exitstatus=$?
        >&2 echo "no image tag found for staging ${staging}"
        exit ${exitstatus}
    fi
}

update_sphinx() {
    ########################################
    # update the sphinx indexes
    ########################################
    echo "Updating sphinx indexes on ${target} with db pattern ${tables} using sphinx image: ${SPHINX_IMAGE_TAG}"
    initialize_git "${SEARCH_GITHUB_FOLDER}" "${SEARCH_GITHUB_REPO}" "${SEARCH_GITHUB_BRANCH}" || :
    # run docker command
    pushd "${SEARCH_GITHUB_FOLDER}" || exit
    DOCKER_LOCAL_TAG="${SPHINX_IMAGE_TAG}" STAGING="${target}" DB="${tables}" make pg2sphinx
    popd || exit
}

# source script until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0
# shellcheck source=./includes.sh
source "${MY_DIR}/includes.sh"
check_env
check_arguments

START_DML=$(date +%s%3N)
echo "$(date +"[%F %T]") start ${COMMAND}"
check_arguments
get_sphinx_image_tag "${target}"
update_sphinx
END_DML=$(date +%s%3N)
echo "$(date +"[%F %T]") finished ${COMMAND} in $(format_milliseconds $((END_DML-START_DML)))"
