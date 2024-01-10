#!/bin/bash

if command -v bats &> /dev/null; then
    echo "Bats not found. Attempting to install..."
    distro=`awk -F= '/^NAME/{print $2}' /etc/os-release`
    if [[ $distro =~ "Ubuntu" ]]; then
        sudo apt-get install -y bats
    else
        sudo yum install -y bats
    fi
fi

source $(dirname "${BASH_SOURCE[0]}")/../../aznhc_env_init.sh
echo $AZ_NHC_ROOT
$AZ_NHC_ROOT/test/bats-unit-test/bats-unit-tests.sh

exit 0
