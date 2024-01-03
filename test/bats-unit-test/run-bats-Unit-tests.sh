#!/bin/bash

sudo apt-get install -y bats &> /dev/null
sudo yum install -y bats &> /dev/null


source $(dirname "${BASH_SOURCE[0]}")/../../aznhc_env_init.sh
echo $AZ_NHC_ROOT
$AZ_NHC_ROOT/test/bats-unit-test/bats-unit-tests.sh
