#!/usr/bin/env bats

source ${AZ_NHC_ROOT:-$NHC_DIR}/test/unit-tests/nhc-test-common.sh
source "$AZ_NHC_ROOT/customTests/azure_gpu_bandwidth.nhc"
source "$AZ_NHC_ROOT/customTests/azure_ib_write_bw_gdr.nhc"
source "$AZ_NHC_ROOT/customTests/azure_nccl_allreduce_ib_loopback.nhc"

setup() {
    SLEEP_TIME=0
    # Background workers cannot update the parent shell's failure flag.
    CHECK_FAILED=0
    function die() { CHECK_FAILED=1; log "ERROR: $*"; }
    function get_ib_numa_node() { echo 0; }
    function print_pkeys() { :; }
    function check_all_reduce_dependencies() { return 0; }
    function nvidia-smi() { printf 'GPU 0\nGPU 1\nGPU 2\nGPU 3\n'; }
    function pass() { log "PASS: $*"; }
    function numactl() {
        # Only the client invocation has a peer hostname.
        [[ "${@: -1}" == "$HOSTNAME" ]] || return 0
        if [[ "$*" == *" -d mlx5_ib2 "* ]]; then
            printf '%s\n' "$IB_RESULT"
        else
            echo "8388608 5000 800.00 800.00 0.011"
        fi
    }
    function mpirun() {
        printf '%s\n' "$NCCL_RESULT"
    }
}

@test "check_nvBW_gpu_bw: Parse nvbandwidth v0.10 result matrices" {
    nvbandwidth_output=$(<"$AZ_NHC_ROOT/test/data/nvbandwidth_v0.10_output.txt")

    parse_nvbandwidth_results "$nvbandwidth_output" 2 "$H2D" "$D2H" "$P2P"

    [[ "${result_lines_array[$H2D]}" == "0     26.03     25.94" ]]
    [[ "${result_lines_array[$D2H]}" == "0     25.97     26.00" ]]
    [[ "${result_lines_array[$P2P]}" == $'0       N/A    276.07\n1    276.19       N/A' ]]
}

@test "check_nvBW_gpu_bw: Reject nvbandwidth output without a result matrix" {
    run parse_nvbandwidth_results \
        $'Running host_to_device_memcpy_ce.\nSUM host_to_device_memcpy_ce 51.97' \
        2 "$H2D"

    [[ "$status" -ne 0 ]]
}

@test "check_nvBW_gpu_bw: Reject an incomplete nvbandwidth result matrix" {
    nvbandwidth_output=$(<"$AZ_NHC_ROOT/test/data/nvbandwidth_v0.10_output.txt")
    nvbandwidth_output="${nvbandwidth_output//$'1    276.19       N/A\n'/}"

    run parse_nvbandwidth_results "$nvbandwidth_output" 2 "$H2D" "$D2H" "$P2P"

    [[ "$status" -ne 0 ]]
}

@test "check_ib_bw_gdr_data_direct: Fail when one worker has low or invalid bandwidth" {
    for IB_RESULT in "8388608 5000 100.00 100.00 0.011" "Couldn't get results" "8388608 5000 nan nan 0.011"; do
        set +e
        result=$(check_ib_bw_gdr_data_direct 640 mlx5_ib0:1 mlx5_ib1:0 mlx5_ib2:3 mlx5_ib3:2; exit "$CHECK_FAILED")
        status=$?
        set -e
        echo "$result"
        [[ "$status" -eq 1 ]]
        [[ $(grep -c "PASS:" <<< "$result") -eq 3 ]]
    done
}

@test "check_nccl_allreduce_ib_loopback: Reject missing or malformed bandwidth" {
    for NCCL_RESULT in "# Out of bounds values : 0 OK" "# Avg bus bandwidth : NaN"; do
        set +e
        result=$(check_nccl_allreduce_ib_loopback 80.0 3 16G "" PHB; exit "$CHECK_FAILED")
        status=$?
        set -e
        echo "$result"
        [[ "$status" -eq 1 ]]
        [[ "$result" != *"test passed"* ]]
        [[ "$result" == *"check_nccl_allreduce_ib_loopback: NCCL allreduce IB loopback produced no valid result in 3 attempts. FaultCode: NHCNA"* ]]
    done
}
