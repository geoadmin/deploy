#!/bin/bash
#
# update sphinx index
MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${MY_DIR}/includes.sh"
check_env

# SPHINX IP's
SPHINX=${SPHINX_DEV};

# SPHINX CONFIG AND TRIGGER
SPHINX_PG_TRIGGER="/etc/sphinxsearch/pg2sphinx_trigger.py"
SPHINX_CONFIG="/etc/sphinxsearch/sphinx.conf"

display_usage() {
    echo -e "Usage:\n$0 -t tables/databases -s staging"
    echo -e "\t-s comma delimited list of tables and/or databases - mandatory"
    echo -e "\t-t target staging - mandatory choose one of '${targets}'"
}

while getopts ":s:t:" options; do
    case "${options}" in
        t)
            target=${OPTARG}
            ;;
        s)
            # convert commas to spaces
            tables=${OPTARG//,/ }
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

    case ${target} in
        dev)
            SPHINX=${SPHINX_DEV};
            ;;

        demo)
            SPHINX=${SPHINX_DEMO};
            ;;

        int)
            SPHINX=${SPHINX_INT};
            ;;

        prod)
            SPHINX=${SPHINX_PROD};
            ;;

        *)
            echo "there is no sphinx host defined for staging ${staging}" >&2
            exit 1
    esac

    [[ ! -z "${SPHINX}" ]] || { echo "please define a sphinx host for ${target}" >&2; exit 1; }
}

update_sphinx() {
    echo "${SPHINX} (${tables} -> ${target})..."
    # connect to sphinx instance and update sphinx indexes
    echo "Updating sphinx indexes"
    echo "sphinx hosts: ${SPHINX}"
    echo "db pattern: ${tables}"
    for sphinx in ${SPHINX}
    do
        echo "opening ssh connection to ${target} sphinx host: ${sphinx} ..."
        ${SSH} -T ${sphinx} /bin/bash << HERE
                if [ -f ${SPHINX_CONFIG} ]; then
                    # silent check of service status, if searchd is not responding stop and start systemctl and searchd
                    if  ! searchd --status  &> /dev/null
                    then
                        echo "sphinx service was not running, trying to start sphinx service on host ${sphinx}"
                        sudo -u sphinxsearch searchd --stop &> /dev/null || :
                        sudo -u root systemctl stop sphinxsearch &> /dev/null || :
                        sleep 5
                        sudo -u root systemctl start sphinxsearch
                        sleep 5
                    fi
                    echo "sphinx service status on host ${sphinx}:"
                    # exit with error if service is still not running
                    searchd --status &> /dev/null || { echo "Sphinx Service is not running on host ${sphinx}" >&2; searchd --status >&2; exit 1; }
                    # update indexes
                    for table in ${tables}
                    do
                        echo "  update sphinx indexes that use the database source: \${table} ..."
                        python -u ${SPHINX_PG_TRIGGER} -d \${table} -c update -s ${SPHINX_CONFIG}
                    done
                    sleep 2
                else
                    echo "could not open sphinx config: ${SPHINX_CONFIG}" >&2
                    exit 1
                fi
HERE
    done
}

# source script until here
[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

check_arguments

START_DML=$(date +%s%3N)
echo "start ${COMMAND}"
check_arguments
update_sphinx
END_DML=$(date +%s%3N)
echo "finished ${COMMAND} in $(format_milliseconds $((END_DML-START_DML)))"
