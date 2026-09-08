#!/usr/bin/env bats

source ${AZ_NHC_ROOT:-$NHC_DIR}/test/unit-tests/nhc-test-common.sh
source "$AZ_NHC_ROOT/customTests/azure_gpu_bandwidth.nhc"

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
