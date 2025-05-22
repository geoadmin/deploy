#!/bin/bash
#
# update sphinx index

MY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# sphinxsearch makefile
SEARCH_GITHUB_BRANCH="master"
SEARCH_GITHUB_REPO="git@github.com-repo-service-search-sphinx:geoadmin/service-search-sphinx.git"
SEARCH_GITHUB_FOLDER="/data/geodata/automata/service-search-sphinx"

# global variable set by get_sphinx_image_tag function
SPHINX_IMAGE_TAG=""

display_usage() {
    echo -e "Usage:\\n$0 -t tables/databases -s staging"
    echo -e "\\t-s comma delimited list of tables and/or databases - mandatory"
    # shellcheck disable=SC2154
    echo -e "\\t-t target staging - mandatory choose one of '${targets}'"
}

validate_dependencies() {
    local dependencies=("git" "curl" "jq" "make" "docker")
    for dep in "${dependencies[@]}"; do
        if ! command -v "${dep}" &>/dev/null; then
            echo "Error: ${dep} is not installed." >&2
            exit 1
        fi
    done
}

while getopts ":s:t:" options; do
    case "${options}" in
    t)
        target=${OPTARG}
        ;;
    s)
        tables=${OPTARG}
        ;;
    \?)
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
        echo "missing a required parameter (source_db -s and target_db -t are required)" >&2
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
        } &>/dev/null
    fi
}

get_service_search_sphinx_version() {
    ########################################
    # gets the version number of service-search-sphinx from the JSON file
    # located at the provided URL
    ########################################
    local staging=$1
    local prefix=""
    local version
    local json_data

    # Declare associative array for domain
    declare -A domain_name
    domain_name[dev]="sys-api3.dev.bgdi.ch"
    domain_name[int]="sys-api3.int.bgdi.ch"
    domain_name[prod]="api3.geo.admin.ch"

    local url="https://${domain_name[$staging]}/rest/services/ech/SearchServer/info"

    # milestone beta images are prefixed with dev- for ecr lifecycle policy
    [[ ${staging} == "dev" ]] && prefix="dev-"


    # Fetch the JSON data from the URL
    if ! json_data=$(retry -d 5 -t 10 -- curl --silent --fail --header "If-None-Match: $(uuidgen)" "${url}"); then
        echo >&2 "Failed to fetch data from ${url}"
        exit 1
    fi

    # Extract the version number using jq
    if ! version=$(echo "${json_data}" | jq -r '.[] | select(.name == "service-search-sphinx") | .version' 2>&1); then
        echo >&2 "Failed to parse JSON data, error: ${version}"
        exit 1
    fi

    # Check if the version is empty
    if [[ -z "${version}" ]]; then
        echo >&2 "No version found for service-search-sphinx in the JSON data"
        exit 1
    fi

    echo "found this version for service-search-sphinx in url ${url} : ${prefix}${version}"
    SPHINX_IMAGE_TAG="${prefix}${version}"
}

update_sphinx() {
    ########################################
    # update the sphinx indexes
    ########################################
    echo "Updating sphinx indexes on ${target} with db pattern ${tables} using sphinx image: ${SPHINX_IMAGE_TAG}"
    initialize_git "${SEARCH_GITHUB_FOLDER}" "${SEARCH_GITHUB_REPO}" "${SEARCH_GITHUB_BRANCH}" || :
    # run docker command
    pushd "${SEARCH_GITHUB_FOLDER}" || exit
    TERM=xterm DOCKER_LOCAL_TAG="${SPHINX_IMAGE_TAG}" STAGING="${target}" DB="${tables}" make pg2sphinx
    popd || exit
}

# source script until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0
# shellcheck source=./includes.sh
source "${MY_DIR}/includes.sh"
validate_dependencies
check_env
check_arguments

START_DML=$(date +%s%3N)
echo "$(date +"[%F %T]") start ${COMMAND}"
check_arguments
get_service_search_sphinx_version "${target}"
update_sphinx
END_DML=$(date +%s%3N)
echo "$(date +"[%F %T]") finished ${COMMAND} in $(format_milliseconds $((END_DML - START_DML)))"
