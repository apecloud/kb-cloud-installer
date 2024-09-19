#!/usr/bin/env bash

source "scripts/log.sh"

actions=("download" "push" "all" "install")
image_base_url="http://kubeblocks-oss.oss-cn-zhangjiakou.aliyuncs.com/images"
chart_base_url="http://kubeblocks-oss.oss-cn-zhangjiakou.aliyuncs.com/charts"
tools_base_url="http://kubeblocks-oss.oss-cn-zhangjiakou.aliyuncs.com/tools"
yq_name="yq_linux_amd64"
skopeo_name="skopeo_linux_amd64"
manifests_file="manifests/manifests.yaml"
values_file="manifests/values.yaml"

if [ "$#" -eq 0 ]; then
    warn "Usage: $0 <action>"
    warn "Available actions: ${actions[*]}"
    exit 1
else
    action=$1
fi

function get_cloud_version() {
    yq eval '.kubeblocks-cloud[0].version' manifests/manifests.yaml
}

function prepare_bins() {
    mkdir -p bin
    wget -nc -P bin ${tools_base_url}/yq/${yq_name}.tar.gz
    wget -nc -P bin ${tools_base_url}/skopeo/${skopeo_name}.tar.gz
}

function prepare_sealos() {
    wget -nc https://kubeblocks-oss.oss-cn-zhangjiakou.aliyuncs.com/artifact/kube-airgap-sealos-v5.0.0.tar.gz
}

function prepare_registry() {
    mkdir -p registry
    cloud_version=$(get_cloud_version)
    wget -nc -P registry "${image_base_url}/kubeblocks-enterprise-${cloud_version}.tar.gz"
    chart_names=$(yq e "to_entries|map(.key)|.[]" ${manifests_file})
    for chart_name in $chart_names; do
        chart_enable=$(yq e ".${chart_name}.enable" ${values_file})
        if [[ "${chart_enable}" == "false" ]]; then
            echo "$(tput -T xterm setaf 3)skip download ${chart_name} images$(tput -T xterm sgr0)"
            continue
        fi
        chart_version=$(yq e ".${chart_name}[0].version" ${manifests_file})
        wget -nc -P registry "${image_base_url}/${chart_name}-${chart_version}.tar.gz"
    done
}

function prepare_charts() {
    cloud_version=$(get_cloud_version)
    wget -nc "${chart_base_url}/kubeblocks-enterprise-charts-${cloud_version}.tgz.gz"
}

# prepare the airgap package, download the required files
function prepare_airgap() {
    prepare_bins
    prepare_sealos
    prepare_registry
    prepare_charts
}

function main() {
    check_supported_engines
    case $action in
        airgap)
            prepare_airgap
            ;;
        push)
            check_images_exist
            prepare_deployment
            push_images
            ;;
        install)
            install
            ;;
        all)
            download_images
            prepare_deployment
            push_images
            install
            ;;
    esac
    version_list
}
main "$@"
