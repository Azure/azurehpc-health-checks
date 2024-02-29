#!/usr/bin/env bats

source $AZ_NHC_ROOT/customTests/azure_common.nhc
source $AZ_NHC_ROOT/test/unit-tests/nhc-test-common.sh

# Load HPC-X
hpcx_init_file=$(find /opt/hpcx* -maxdepth 1 -name "hpcx-init.sh")
source $hpcx_init_file
hpcx_load

gpu_test=( "azure_gpu_count.nhc" "azure_gpu_bandwidth.nhc" "azure_gpu_ecc.nhc" "azure_nccl_allreduce.nhc" "azure_ib_write_bw_gdr.nhc" "azure_ib_write_bw_non_gdr.nhc")


for check in "${gpu_test[@]}" ; do
    source $AZ_NHC_ROOT/customTests/$check
done

@test "Pass case: check_gpu_count" {
    set +e
    gpu_count=$(nvidia-smi --list-gpus | wc -l)
    result=$(check_gpu_count $gpu_count)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_gpu_count" {
    set +e
    result=$(check_gpu_count 10)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_gpu_bw" {
    set +e
    result=$(check_gpu_bw 1 1)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_gpu_bw" {
    set +e
    result=$(check_gpu_bw 500 500)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_gpu_ecc" {
    set +e
    result=$(check_gpu_ecc 1 1)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_gpu_ecc" {
    set +e
    result=$(check_gpu_ecc -1 -1)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_nccl_allreduce" {
    set +e
    topo_file=$(get_topofile)
    result=$(check_nccl_allreduce 1.0 1 $topo_file 8G)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_nccl_allreduce" {
    set +e
    topo_file=$(get_topofile)
    result=$(check_nccl_allreduce 600.0 1 $topo_file 8G)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_ib_bw" {
    set +e
    ib_type=$(get_ib_type)
    if [[ $ib_type == "gdr" ]]; then
        result=$(check_ib_bw_gdr 1.0)
    elif [[ $ib_type == "non_gdr" ]]; then
        result=$(check_ib_bw_non_gdr 1.0)
    else
        # no IB test, set to passing case
        result="PASS"
    fi
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_ib_bw" {
    set +e
    ib_type=$(get_ib_type)
    if [[ $ib_type == "gdr" ]]; then
        result=$(check_ib_bw_gdr 1000.0)
    elif [[ $ib_type == "non_gdr" ]]; then
        result=$(check_ib_bw_non_gdr 1000.0)
    else
        # no IB test, set to passing case
        result="ERROR"
    fi
    set -e
    [[ "$result" == *"ERROR"* ]]
}
