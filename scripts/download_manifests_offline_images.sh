#!/bin/bash
MANIFESTS_FILE=${1:-"deploy-manifests.yaml"}
VALUES_FILE=${2:-"deploy-values.yaml"}
PARALLEL_DOWNLOAD=${3:-"true"}
MAX_PARALLEL_NUM=4
PARALLEL_FILE="download_manifests_offline_images_parallel.txt"
PACKAGE_DIR="manifests_offline_images_package"
TOOLS_BASE_URL="http://kubeblocks-oss.oss-cn-zhangjiakou.aliyuncs.com/tools"
IMAGE_BASE_URL="http://kubeblocks-oss.oss-cn-zhangjiakou.aliyuncs.com/images"


download_images_package() {
    image_package_name=$1
    image_package_version=$2

    if [[ "${PARALLEL_DOWNLOAD}" == "true" ]]; then
        cur_parallel_num=$(cat "${PARALLEL_FILE}")
        if [[ $cur_parallel_num -lt ${MAX_PARALLEL_NUM} ]]; then
            cur_parallel_num=$((cur_parallel_num + 1))
            echo $cur_parallel_num > "${PARALLEL_FILE}"
        fi
    fi

    for i in {1..3}; do
        image_package_url="${IMAGE_BASE_URL}/${image_package_name}-images-${image_package_version}.tar.gz"
        wget -nc -P ${PACKAGE_DIR} ${image_package_url}
        ret_wget=$?
        if [[ $ret_msg -eq 0 ]]; then
            echo "$(tput -T xterm setaf 2)download image ${image_package_name} ${image_package_version} package success$(tput -T xterm sgr0)"
            break
        fi
        sleep 1
    done

    if [[ "${PARALLEL_DOWNLOAD}" == "true" ]]; then
        cur_parallel_num=$(cat "${PARALLEL_FILE}")
        if [[ $cur_parallel_num -gt 0 ]]; then
            cur_parallel_num=$((cur_parallel_num - 1))
            echo $cur_parallel_num > "${PARALLEL_FILE}"
        fi
    fi

}

main() {
    if [[ ! -f "${MANIFESTS_FILE}" || ! -f "${VALUES_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)Not found manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
        return
    fi

    TOOL_CLI="$( command -v yq )"
    if [[ -z "$TOOL_CLI" ]]; then
        echo "$(tput -T xterm setaf 1)Not found yq tools$(tput -T xterm sgr0)"
        return
    fi
    mkdir -p ${PACKAGE_DIR}

    if [[ "${PARALLEL_DOWNLOAD}" == "true" ]]; then
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
            if [[ "${PARALLEL_DOWNLOAD}" == "true" ]]; then
                while [[ $(cat "${PARALLEL_FILE}") -ge ${MAX_PARALLEL_NUM} ]]; do
                    sleep 1
                done
                 # 并行下载
                download_images_package "$chart_name" "$chart_version" &
            else
                # 串行下载
                download_images_package "$chart_name" "$chart_version"
            fi
        fi
    done
    if [[ "${PARALLEL_DOWNLOAD}" == "true" ]]; then
        wait
    fi
    echo "
      Download images package done!
    "
    if [[ "${PARALLEL_DOWNLOAD}" == "true" ]]; then
        rm -rf "${PARALLEL_FILE}"
    fi
}

main "$@"
