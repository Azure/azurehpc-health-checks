#!/usr/bin/env bats

source $NHC_DIR/customTests/azure_common.nhc
export AZ_NHC_ROOT=$NHC_DIR
source /opt/hpcx-v2.16-gcc-mlnx_ofed-ubuntu22.04-cuda12-gdrcopy2-nccl2.18-x86_64/hpcx-init.sh 
hpcx_load

function die() {
    log "ERROR:  $NAME:  Health check failed:  $*"
}

function dbg() {
    log "dbg: $*"
}

function log() {
    echo $*
}

gpu_test=( "azure_gpu_count.nhc" "azure_gpu_bandwidth.nhc" "azure_gpu_ecc.nhc" "azure_nccl_allreduce.nhc" "azure_ib_write_bw_gdr.nhc" )

cpu_test=( "azure_cpu_stream.nhc" "azure_ib_write_bw_non_gdr.nhc")
         
for check in "${gpu_test[@]}" ; do
    source $NHC_DIR/customTests/$check
done

@test "Pass case: check_cpu_stream" {
    set +e

    result=$(check_cpu_stream 1.0)

    set -e
    [[ "$result" != *"ERROR"* ]]
}

@test "Fail case: check_cpu_stream" {
    set +e
    result=$(check_cpu_stream 900000.0)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_ib_bw_gdr" {
    set +e
    result=$(check_ib_bw_non_gdr 1.0)
    set -e
    [[ "$result" != *"ERROR"* ]]
}

@test "Fail case: check_ib_bw_gdr" {
    set +e
    result=$(check_ib_bw_non_gdr 1000.0)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

