#!/bin/bash
# Enable strict error handling
set -Eeuo pipefail
# Enable the inherit_errexit option to ensure that any command failure in a subshell causes the script to exit
shopt -s inherit_errexit

SNAPSHOT=20241218


snapshot_bod() {
    bash deploy.sh -s bod_master -a "${SNAPSHOT}"
}

deploy() {
    # Function: deploy
    # Description: This function deploys various datasets to a specified target environment.
    # Parameters:
    #   $1 - The target environment to deploy to. Possible values are "dev", "int" (integration), or "prod" (production).
    #
    # The function performs the following steps:
    # 1. Sets the source environment based on the target environment.
    #    - If the target is "int", the source is set to "dev".
    #    - If the target is "prod", the source is set to "int".
    # 2. Adds an additional parameter "-y" if the target is "int" or "prod".
    # 3. Executes a series of `bash deploy.sh` commands to deploy datasets from the source environment to the target environment.
    #    - The datasets include various schemas and tables from "stopo", "evd", and "bafu" sources.
    #    - Each deploy command includes the source schema, target environment, and any additional parameters.
    target=$1
    local source=master
    local additional_param=()

    if [[ "${target}" != "dev" && "${target}" != "int" && "${target}" != "prod" ]]; then
        echo "Invalid target environment: ${target}" >&2
        echo "Valid targets are: dev, int, prod" >&2
        exit 1
    fi

    if [ "${target}" = "int" ]; then
        source="dev"
        additional_param+=("-y")
    elif [ "${target}" = "prod" ]; then
        source="int"
        additional_param+=("-y")
    fi

    # bod deploy from snaphsot
    bash deploy.sh -s bod_master"${SNAPSHOT}" -t "${target}" -y

    bash deploy.sh -s stopo_"${source}" -r false -d false -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s stopo_"${source}".karto.ski_network -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s stopo_"${source}".karto.ski_routes -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s stopo_"${source}".tlm.prodas_spatialseltype_land -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s stopo_"${source}".tlm.prodas_spatialseltype_kanton -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s stopo_"${source}".tlm.prodas_spatialseltype_bezirk -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s stopo_"${source}".tlm.swissboundaries_gemeinden_fill_hist -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s stopo_"${source}".tlm.swissboundaries_hoheitsgrenze_hist -t "${target}" "${additional_param[@]}"

    bash deploy.sh -s evd_"${source}" -r false -d false -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s evd_"${source}".bazl.wohngebiete_aulav -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s evd_"${source}".sbfi.sachplan_cern_anhoerung_fac_pnt -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s evd_"${source}".sbfi.sachplan_cern_anhoerung_fac_line -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s evd_"${source}".sbfi.sachplan_cern_anhoerung_plm_poly -t "${target}" "${additional_param[@]}"

    bash deploy.sh -s bafu_"${source}" -r false -d false -t "${target}" "${additional_param[@]}"
    bash deploy.sh -s bafu_"${source}".lebensraumkarte.lebensraumkarte_schweiz -t "${target}" "${additional_param[@]}"
}

[ "$0" = "${BASH_SOURCE[*]}" ] || return 0

snapshot_bod
deploy dev
#deploy int
#deploy prod
