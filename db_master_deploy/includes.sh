#!/bin/bash
set -Ee
set -o pipefail
export LC_ALL=C
USER=$(logname) # get user behind sudo su -
# if trigger script is called by deploy.sh, log parents pid in syslog
# PARENT_COMMAND: you will get empty_string if it was invoked by user and name_of_calling_script if it was invoked by other script.
PARENT_COMMAND=$(ps $PPID | tail -n 1 | awk "{print \$6}")
RDS_WRITER_HOST="pg-geodata-master.bgdi.ch"
SYSLOGPID=$$

comment="manual db deploy"
if [ "${message}" ]; then
    comment="${message}"
fi

INFO="${0##*/} - ${USER} - ${comment} - [${SYSLOGPID}] - INFO"
ERROR="${0##*/} - ${USER} - ${comment} - [${SYSLOGPID}] - ERROR"

COMMAND="${0##*/} $* (pid: $$)"
PSQL() {
    psql -X -h ${RDS_WRITER_HOST} "$@"
}

DROPDB() {
    dropdb -h ${RDS_WRITER_HOST} "$@"
}

CREATEDB() {
   createdb -h ${RDS_WRITER_HOST} --strategy=file_copy "$@"
}

PG_DUMP() {
    pg_dump -h ${RDS_WRITER_HOST} "$@"
}

# coloured output
red='\e[0;31m'
NC='\e[0m' # No Color

# space delimited list of valid deploy targets, the target will be used as database suffix
targets="dev int prod demo tile"
targets_toposhop="dev int"

#######################################
# Logging
# Globals:
#   INFO
# Arguments:
#   pipe data
# Returns:
#   prefixed stdout to screen and syslog
#######################################
log () {
    exec 40> >(exec logger -t "${INFO}")
    local data
    while read data
    do
        echo "INFO: $1${data}"
        echo "$1${data}" >&40
    done
    exec 40>&-
}

#######################################
# Error Logging
# Globals:
#   ERROR
# Arguments:
#   pipe data
# Returns:
#   prefixed stderr to screen and syslog
#######################################
err() {
    exec 40> >(exec logger -t "${ERROR}" )
    local data
    while read data
    do
        echo -e "${red}ERROR: $1${data}${NC}" >&2
        echo "$1${data}" >&40
    done
    exec 40>&-
}

#######################################
# Ceiling,
# the smallest integer value greater than or equal to $1/$2
# Globals:
#   None
# Arguments:
#   $1 integer -> dividend
#   $2 integer -> divisor
# Returns:
#   integer
#######################################
Ceiling () {
    DIVIDEND="${1}"
    DIVISOR="${2}"
    if [ $(( DIVIDEND % DIVISOR )) -gt 0 ]; then
            RESULT=$(( ( ( DIVIDEND - ( DIVIDEND % DIVISOR ) ) / DIVISOR ) + 1 ))
    else
            RESULT=$(( DIVIDEND / DIVISOR ))
    fi
    echo "${RESULT}"
}

#######################################
# pretty print milliseconds
# Globals:
#   None
# Arguments:
#   milliseconds
# Returns:
#   formatted string
#######################################
format_milliseconds() {
    seconds=$(($1/1000))
    printf '%dh:%dm:%ds.%d - %d milliseconds\n' $((seconds/3600)) $((seconds%3600/60)) $((seconds%60)) $(($1 % 1000)) "$1"
}

redirect_output() {
    exec 5>&1
    exec 6>&2
    # stdout to log function
    exec 1> >(log)
    # stdout to err function
    exec 2> >(err)
}

# check environment variables
check_env() {
    # check for deploy.cfg, if exists read variables from file
    MY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

    if [[ -f "${MY_DIR}/deploy.cfg" ]]; then
        source "${MY_DIR}/deploy.cfg"
    fi

    # check for lock dir, create it if it does not exist
    readonly LOCK_DIR="${MY_DIR}/tmp.lock"
    readonly LOCK_FD=200
    [ -d "${LOCK_DIR}" ] || mkdir "${LOCK_DIR}" -p

    local failed=false
    # DB superuser, set and not empty
    if [[ -z "${PGUSER}" ]]; then
        echo 'export env variable containing DB Superuser name: $ export PGUSER=xxx' >&2
        failed=true
    fi
    if [[ "${failed}" = true ]];then
        echo "you can set the variables in ${MY_DIR}/deploy.cfg" >&2
        exit 1
    fi
    # force geodata
    if [[ $(whoami) != "geodata" ]];
    then
        echo "This script must be run as geodata!" >&2
        exit 1
    fi
}

# if sourced by deploy.sh
if [[ "$(basename "${BASH_SOURCE[1]}")" == "deploy.sh" ]]; then
    SYSLOGPID="${PPID}..$$"
    redirect_output
fi
