#!/bin/bash

set +e
set -o nounset
REGISTRY_ADDRESS=${1:-""}
REGISTRY_USERNAME=${2:-""}
REGISTRY_PASSWORD=${3:-""}
MANIFESTS_FILE=${4:-"manifests.yaml"}
VALUES_FILE=${5:-"values.yaml"}
PARALLEL_LOAD=${6:-"true"}
PACKAGE_DIR="manifests_offline_images_package"
MAX_PARALLEL_NUM=4
PARALLEL_FILE="load_manifests_offline_images_parallel.txt"


check_push_tool() {
    TOOL_CLI="$( command -v docker )"
    if [[ -z "$TOOL_CLI" ]]; then
        TOOL_CLI="$( command -v sealos )"
    fi

    if [[ -n "$TOOL_CLI" ]]; then
        TOOL_CLI=${TOOL_CLI##*/}
    fi
}

login_registry() {
    if [[ -z "$REGISTRY_USERNAME" || -z "$REGISTRY_PASSWORD" ]]; then
        return
    fi
    echo "Logging into registry: $REGISTRY_ADDRESS"
    for i in {1..3}; do
        echo "${REGISTRY_PASSWORD}" | ${TOOL_CLI} login --password-stdin --username "${REGISTRY_USERNAME}" "${REGISTRY_ADDRESS}"
        login_ret=$?
        if [ $login_ret -eq 0 ]; then
            break
        fi
        echo "retry login registry: $REGISTRY_ADDRESS"
        sleep 1
    done
}

load_package_images() {
    image_package_name=$1
    image_package_version=$2

    image_package_name="${image_package_name}-images-${image_package_version}.tar.gz"
    image_package_path="${image_package_name}"
    if [[ ! -f "${image_package_path}" ]]; then
        image_package_path="${PACKAGE_DIR}/${image_package_name}"
    fi

    if [[ ! -f "${image_package_path}" ]]; then
        echo "Not found image package $image_package_name"
        return
    fi

    if [[ "${PARALLEL_LOAD}" == "true" ]]; then
        cur_parallel_num=$(cat "${PARALLEL_FILE}")
        if [[ $cur_parallel_num -lt ${MAX_PARALLEL_NUM} ]]; then
            cur_parallel_num=$((cur_parallel_num + 1))
            echo $cur_parallel_num > "${PARALLEL_FILE}"
        fi
    fi

    echo "Loading image from file: $image_package_path"
    for i in {1..3}; do
        ${TOOL_CLI} load -i "$image_package_path"
        load_ret=$?
        if [[ $load_ret -eq 0 ]]; then
            break
        fi
        echo "retry load image from file: $image_package_path"
        sleep 1
    done

    if [[ "${PARALLEL_LOAD}" == "true" ]]; then
        cur_parallel_num=$(cat "${PARALLEL_FILE}")
        if [[ $cur_parallel_num -gt 0 ]]; then
            cur_parallel_num=$((cur_parallel_num - 1))
            echo $cur_parallel_num > "${PARALLEL_FILE}"
        fi
    fi

}

load_image_package() {
    if [[ ! -f "${MANIFESTS_FILE}" || ! -f "${VALUES_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)Not found manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
        return
    fi

    if [[ "${PARALLEL_LOAD}" == "true" ]]; then
        touch "${PARALLEL_FILE}"
        echo 0 > "${PARALLEL_FILE}"
    fi

    enable_charts=$(yq e "to_entries|map(.key)|.[]"  ${VALUES_FILE})
    for chart_name in $(echo "$enable_charts"); do
        chart_enable=$(yq e ".${chart_name}.enable" ${VALUES_FILE})
        chart_version=$(yq e ".${chart_name}[0].version" ${MANIFESTS_FILE})
        is_addon=$(yq e ".${chart_name}[0].isAddon" ${MANIFESTS_FILE})
        if [[ "${chart_name}" == "kubeblocks-cloud" ]]; then
            chart_name="kubeblocks-enterprise"
        fi
        if [[ "${chart_enable}" == "true" && -n "${chart_version}" && "${is_addon}" == "true" ]]; then
            if [[ "${PARALLEL_LOAD}" == "true" ]]; then
                while [[ $(cat "${PARALLEL_FILE}") -ge ${MAX_PARALLEL_NUM} ]]; do
                    sleep 1
                done
                 # 并行load
                load_package_images "$chart_name" "$chart_version" &
            else
                # 串行load
                load_package_images "$chart_name" "$chart_version"
            fi
        fi
    done
    if [[ "${PARALLEL_LOAD}" == "true" ]]; then
        wait
    fi
    echo "
      Load images package done!
    "
    if [[ "${PARALLEL_LOAD}" == "true" ]]; then
        rm -rf "${PARALLEL_FILE}"
    fi
}

push_images() {
    images_list_all=""
    if [[ "${TOOL_CLI}" == *"sealos" ]]; then
        images_list_all=$( sealos images --all --format "{{.Name}}:{{.Tag}}" )
    else
        images_list_all=$( docker images --all --format "{{.Repository}}:{{.Tag}}" )
    fi
    images_ret=$?
    if [ $images_ret -ne 0 ]; then
        images_list_all=$( ${TOOL_CLI} images --all | awk '{print $1":"$2}' | grep -v "REPOSITORY:TAG" )
    fi

    if [[ -z "${images_list_all}" ]]; then
        echo "$(tput -T xterm setaf 3)Not found images!$(tput -T xterm sgr0)"
        return
    fi

    pushed_images_list=$( echo "$images_list_all" | (grep "${REGISTRY_ADDRESS}" || true) )
    images_list=$( echo "$images_list_all" | grep -v "${REGISTRY_ADDRESS}" )

    for image in ${images_list}; do
        new_image=""
        count=$(echo "${image}" | grep -o "/" | wc -l | tr -cd '0-9')
        case $count in
            0|1)
                new_image="${REGISTRY_ADDRESS}/${image}"
            ;;
            *)
                new_image=${image#*/}
                new_image="${REGISTRY_ADDRESS}/${new_image}"
            ;;
        esac

        pushed_new_image=0
        for pushed_image in ${pushed_images_list}; do
            if [[ "${pushed_image}" == "$new_image" ]]; then
                pushed_new_image=1
                break
            fi
        done

        if [[ $pushed_new_image -eq 1 ]]; then
            continue
        fi
        echo "$new_image"
        for i in {1..3}; do
            ${TOOL_CLI} tag "$image" "$new_image"
            tag_ret=$?
            if [ $tag_ret -eq 0 ]; then
                break
            fi
            echo "retry tag $image to $new_image"
            sleep 1
        done

        for i in {1..3}; do
            ${TOOL_CLI} push "$new_image"
            push_ret=$?
            if [ $push_ret -eq 0 ]; then
                break
            fi
            echo "retry "
            sleep 1
        done
    done
    echo "
      Push images done!
    "
}

main() {
    local TOOL_CLI=""

    if [[ -z "$REGISTRY_ADDRESS" ]]; then
        echo "$(tput -T xterm setaf 1)Please provide registry address!$(tput -T xterm sgr0)"
        return
    fi

    check_push_tool

    if [[ -z "${TOOL_CLI}" ]]; then
        echo "$(tput -T xterm setaf 1)Not found push tool!$(tput -T xterm sgr0)"
        return
    fi

    login_registry

    load_image_package

    push_images
}

main "$@"