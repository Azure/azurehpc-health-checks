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

# check_gpu_memtest: a stub "pantheon" executable stands in for the real tool,
# so these tests run without a GPU.
@test "check_gpu_memtest: Pass when pantheon exits 0" {
    source "$AZ_NHC_ROOT/customTests/azure_gpu_memtest.nhc"
    stub=$(mktemp)
    printf '#!/bin/bash\nexit 0\n' > "$stub"
    chmod +x "$stub"
    PANTHEON_BIN="$stub" run check_gpu_memtest 1
    rm -f "$stub"

    [[ "$status" -eq 0 ]]
    [[ "$output" != *"ERROR"* ]]
}

@test "check_gpu_memtest: Fail when pantheon reports memory errors" {
    source "$AZ_NHC_ROOT/customTests/azure_gpu_memtest.nhc"
    stub=$(mktemp)
    printf '#!/bin/bash\necho "Verification: FAIL (1 march errors over 1 passes)"\nexit 1\n' > "$stub"
    chmod +x "$stub"
    PANTHEON_BIN="$stub" run check_gpu_memtest 1
    rm -f "$stub"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"memory errors detected"* ]]
}

@test "check_gpu_memtest: Fail when pantheon exceeds the timeout" {
    source "$AZ_NHC_ROOT/customTests/azure_gpu_memtest.nhc"
    stub=$(mktemp)
    printf '#!/bin/bash\nsleep 30\n' > "$stub"
    chmod +x "$stub"
    GPU_MEMTEST_TIMEOUT_MARGIN=1 PANTHEON_BIN="$stub" run check_gpu_memtest 1
    rm -f "$stub"

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"did not finish"* ]]
}

@test "check_gpu_memtest: Skip when pantheon is not installed" {
    source "$AZ_NHC_ROOT/customTests/azure_gpu_memtest.nhc"
    PANTHEON_BIN=/nonexistent/pantheon run check_gpu_memtest 1

    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipping"* ]]
}

@test "check_gpu_memtest: Reject an invalid duration" {
    source "$AZ_NHC_ROOT/customTests/azure_gpu_memtest.nhc"
    run check_gpu_memtest abc

    [[ "$status" -ne 0 ]]
    [[ "$output" == *"ERROR"* ]]
}
