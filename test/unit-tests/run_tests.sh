#!/bin/bash

# Install bats if necessary
if ! command -v bats &> /dev/null ; then
    echo "Bats not found. Attempting to install..."
    distro_check=$( cat /etc/os-release | grep -i ID_LIKE=)
    echo $distro_check
    if [[ $distro_check =~ "debian" ]]; then
        sudo apt-get install -y bats
    else
        sudo yum install -y epel-release
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
source $NHC_DIR/test/unit-tests/nhc-test-common.sh

echo "Running integration tests"
bats --pretty ${parent_dir}/basic-unit-test.sh
integration_test_status=$?

echo "Running nhc custom checks tests"

if lspci | grep -iq NVIDIA ; then
    NVIDIA_RT="--runtime=nvidia"
fi

sudo docker run -itd --name=aznhc --net=host -e TIMEOUT=500 --rm \
${NVIDIA_RT} --cap-add SYS_ADMIN --cap-add=CAP_SYS_NICE \
--shm-size=8g \
--privileged -v /sys:/hostsys/ \
-v $NHC_DIR/customTests:/azure-nhc/customTests \
-v $NHC_DIR/test:/azure-nhc/test \
mcr.microsoft.com/aznhc/aznhc-nv bash

sudo docker exec -it aznhc bash -c "cp /azure-nhc/customTests/azure_common.nhc /etc/nhc/scripts/"

if lspci | grep -iq NVIDIA ; then
    echo "Running GPU Unit tests"
    sudo docker exec -it aznhc bash -c "bats --pretty /azure-nhc/test/unit-tests/nhc-gpu-test.sh"
    unit_test_status=$?
elif lspci | grep -iq AMD ; then
	# AMD installs
    echo "No unit tests for AMD GPU SKUs"
else
    sudo docker exec -it aznhc bash -c "bats --pretty /azure-nhc/test/unit-tests/nhc-cpu-test.sh"
    unit_test_status=$?
fi

# Other hardware unit tests
sudo docker exec -it aznhc bash -c "bats --pretty /azure-nhc/test/unit-tests/nhc-hardware-test.sh"

sudo docker container stop aznhc

exit $((unit_test_status || integration_test_status))
