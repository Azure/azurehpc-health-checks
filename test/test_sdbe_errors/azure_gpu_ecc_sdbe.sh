#!/usr/bin/env bats
echo "# ~/customTests/azure_common.nhc" >&3
source $AZ_NHC_ROOT/customTests/azure_common.nhc
source $AZ_NHC_ROOT/test/unit-tests/nhc-test-common.sh

# Load HPC-X
hpcx_init_file=$(find /opt/hpcx* -maxdepth 1 -name "hpcx-init.sh")
source $hpcx_init_file
hpcx_load

gpu_test="azure_gpu_ecc.nhc"
source $AZ_NHC_ROOT/customTests/$gpu_test

# Check Page Retirement Table Full error
@test "Check Page Retirement Command" {
    set +e
    retirement_table=$(nvidia-smi - -d PAGE_RETIREMENT)
    result=$(collect_ecc_data "SDBE")
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [ "$status" -eq 0 ]
}

@test "Check Page Retirement Table Full error" {
    set +e
    retirement_table=$(nvidia-smi - -d PAGE_RETIREMENT)
    result=$(check_SDBE_ecc)
    status=$?
    echo $output
    set -e
    [[ "$result" != *"ERROR"* ]] && [ "$status" -eq 0 ]
}
