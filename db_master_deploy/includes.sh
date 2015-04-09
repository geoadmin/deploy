#!/bin/bash
set -e
set -o pipefail
USER=$(logname) # get user behind sudo su - 
INFO="${0##*/} - $USER - [$$] - INFO"
ERROR="${0##*/} - $USER - [$$] - ERROR"
locktext="${0##*/} - [$$] locked by $USER @ $(date +"%F %T")"
lockfile="/tmp/db_deploy.lock"

# space delimited list of valid deploy targets, the target will be used as database suffix
targets="dev int prod demo"

log () {
    exec 40> >(exec logger -t "$INFO")
    local data
    while read data
    do
        echo "INFO: $1$data"
        echo "$1$data" >&40
    done
    exec 40>&- 
}

err() {
    exec 40> >(exec logger -t "$ERROR" )
    local data
    while read data
    do
        echo "$(tput setaf 1)ERROR: $1$data$(tput sgr0)" >&2
        echo "$1$data" >&40
    done    
    exec 40>&- 
}

Ceiling () {
  python -c "from math import ceil; print int(ceil(float($1)/float($2)))"
}


format_milliseconds() {
    seconds=$(($1/1000))
    printf '%dh:%dm:%ds.%d - %d milliseconds\n' $(($seconds/3600)) $(($seconds%3600/60)) $(($seconds%60)) $(($1 % 1000)) $1
}

exec 5>&1
exec 6>&2
# stdout to log function
exec 1> >(log)
# stdout to err function
exec 2> >(err)

# force geodata
if [[ $(whoami) != "geodata" ]]; then echo "This script must be run as geodata!" >&2 ; exit 1; fi
