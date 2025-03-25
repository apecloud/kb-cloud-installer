#!/bin/bash
OSS_ACCESS_KEY_ID=${1:-""}
OSS_ACCESS_KEY_SECRET=${2:-""}
MANIFESTS_FILE=${3:-"manifests.yaml"}
VALUES_FILE=${4:-"values.yaml"}
ARM64_FLAG=${5:-"false"}
PARALLEL_DOWNLOAD=${6:-"true"}

MAX_PARALLEL_NUM=4
PARALLEL_FILE="download_manifests_offline_images_parallel.txt"
PACKAGE_DIR="manifests_offline_images_package"
IMAGE_BASE_URL="oss://kubeblocks-oss/images"
CHART_BASE_URL="oss://kubeblocks-oss/charts"
OSS_ENDPOINT="oss-cn-zhangjiakou.aliyuncs.com"

if [[ "${ARM64_FLAG}" == "true" || "${ARM64_FLAG}" == "arm" || "${ARM64_FLAG}" == "arm64" ]]; then
    IMAGE_BASE_URL="${IMAGE_BASE_URL}/arm64"
fi

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

    image_package_url="${IMAGE_BASE_URL}/${image_package_name}-images-${image_package_version}.tar.gz"
    echo "download image ${image_package_name} ${image_package_version}..."
    for i in {1..3}; do
        ossutil cp -rf --checkpoint-dir=${PACKAGE_DIR}/tmp ${image_package_url} ./${PACKAGE_DIR}
        ret_cp=$?
        if [[ $ret_cp -eq 0 ]]; then
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

download_charts_package() {
    chart_package_name=$1
    chart_package_version=$2

    chart_package_url="${CHART_BASE_URL}/${chart_package_name}-charts-${chart_package_version}.tar.gz"
    echo "download chart ${chart_package_name} ${chart_package_version}..."
    for i in {1..3}; do
        ossutil cp -rf --checkpoint-dir=${PACKAGE_DIR}/tmp ${chart_package_url} ./${PACKAGE_DIR}
        ret_cp=$?
        if [[ $ret_cp -eq 0 ]]; then
            echo "$(tput -T xterm setaf 2)download chart ${chart_package_name} ${chart_package_version} package success$(tput -T xterm sgr0)"
            break
        fi
        sleep 1
    done
}

check_oss_tool() {
    OSSUTIL_CLI="$( command -v ossutil )"
    if [[ -n "$OSSUTIL_CLI" ]]; then
        return
    fi
    echo "Install ossutil..."
    for i in {1..3}; do
        curl -fsSL https://gosspublic.alicdn.com/ossutil/install.sh | sudo bash
        ret_install=$?
        if [[ $ret_install -eq 0 ]]; then
            echo "$(tput -T xterm setaf 2)Install ossutil success$(tput -T xterm sgr0)"
            break
        fi
        sleep 1
    done

}

oss_config() {
    check_oss_tool
    for i in {1..3}; do
        ossutil config --endpoint=${OSS_ENDPOINT} --access-key-id=${OSS_ACCESS_KEY_ID} --access-key-secret=${OSS_ACCESS_KEY_SECRET}
        ret_config=$?
        if [[ $ret_config -eq 0 ]]; then
            echo "$(tput -T xterm setaf 2)Config ossutil success$(tput -T xterm sgr0)"
            break
        fi
        sleep 1
    done
}

main() {
    if [[ -z "${OSS_ACCESS_KEY_ID}" || -z "${OSS_ACCESS_KEY_SECRET}" ]]; then
        echo "$(tput -T xterm setaf 1)Please provide oss access credential!$(tput -T xterm sgr0)"
        return
    fi

    if [[ ! -f "${MANIFESTS_FILE}" || ! -f "${VALUES_FILE}" ]]; then
        echo "$(tput -T xterm setaf 1)Not found manifests file:${MANIFESTS_FILE}$(tput -T xterm sgr0)"
        return
    fi

    oss_config

    OSSUTIL_CLI="$( command -v ossutil )"
    if [[ -z "$OSSUTIL_CLI" ]]; then
        echo "$(tput -T xterm setaf 1)Not found ossutil tools$(tput -T xterm sgr0)"
        return
    fi

    TOOL_CLI="$( command -v yq )"
    if [[ -z "$TOOL_CLI" ]]; then
        echo "$(tput -T xterm setaf 1)Not found yq tools$(tput -T xterm sgr0)"
        return
    fi
    mkdir -p ${PACKAGE_DIR}
    mkdir -p ${PACKAGE_DIR}/tmp

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
            download_charts_package "$chart_name" "$chart_version"
        fi

        if [[ "${chart_enable}" == "true" && -n "${chart_version}" && ("${is_addon}" == "true" || "${chart_name}" == "kubeblocks-enterprise") ]]; then
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
