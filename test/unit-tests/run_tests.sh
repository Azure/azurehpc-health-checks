#!/bin/bash

# Install bats if necessary
if ! command -v bats &> /dev/null; then
    echo "Bats not found. Attempting to install..."
    distro=`awk -F= '/^NAME/{print $2}' /etc/os-release`
    if [[ $distro_check =~ "debian" ]]; then
        sudo apt-get install -y bats
    else
        sudo yum install epel-release
        sudo yum install -y bats
    fi
fi

NHC_DIR=$1

script_path="$(realpath "$0")"
parent_dir="$(dirname "$script_path")"
if [ -z "$NHC_DIR" ]; then
    NHC_DIR="$(realpath "$parent_dir/../..")"
    echo "NHC_DIR not set. Using default: $NHC_DIR"
fi

export NHC_DIR

echo "Running basic tests"
bats --pretty ${parent_dir}/basic-unit-test.sh

echo "Running nhc custom checks tests"
if lspci | grep -iq NVIDIA ; then
    bats --pretty ${parent_dir}/nhc-gpu-test.sh
elif lspci | grep -iq AMD ; then
	# AMD installs
    echo "No unit tests for AMD GPU SKUs"
else
    bats --pretty ${parent_dir}/nhc-cpu-test.sh
fi

exit 0
