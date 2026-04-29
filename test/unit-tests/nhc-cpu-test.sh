#!/usr/bin/env bats

# Source nhc-test-common.sh first: it provides the AZ_NHC_ROOT fallback
# needed when running on the host with only NHC_DIR set.
source ${AZ_NHC_ROOT:-$NHC_DIR}/test/unit-tests/nhc-test-common.sh
source $AZ_NHC_ROOT/customTests/azure_common.nhc


cpu_test=( "azure_cpu_stream.nhc" "azure_ib_write_bw_non_gdr.nhc")
         
for check in "${cpu_test[@]}" ; do
    source $AZ_NHC_ROOT/customTests/$check
done

@test "Pass case: check_cpu_stream" {
    set +e
    result=$(check_cpu_stream 1.0)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_cpu_stream" {
    set +e
    result=$(check_cpu_stream 900000.0)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_ib_bw_non_gdr" {
    set +e
    result=$(check_ib_bw_non_gdr 1.0)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_ib_bw_non_gdr" {
    set +e
    result=$(check_ib_bw_non_gdr 1000.0)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

