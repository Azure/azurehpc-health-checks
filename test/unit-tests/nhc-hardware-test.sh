#!/usr/bin/env bats

# Hardware tests for Azure NHC that are not GPU or CPU specific

source $NHC_DIR/customTests/azure_common.nhc
source $NHC_DIR/test/unit-tests/nhc-test-common.sh

# Enumerate over currently tested hardware checks
hardware_test=( "azure_nvme_count.nhc" )

# Load the hardware checks
for check in "${hardware_test[@]}" ; do
    source $NHC_DIR/customTests/$check
done

## NVME Count Unit Tests

# Given a directory and a count, create mock NVMe devices as empty files
# Ex - 
# Input - /tmp/tmp.mNtJgqCZC5 4 
# Output - 
# /tmp/tmp.mNtJgqCZC5/dev/nvme3n1
# /tmp/tmp.mNtJgqCZC5/dev/nvme1n1
# /tmp/tmp.mNtJgqCZC5/dev/nvme0n1
# /tmp/tmp.mNtJgqCZC5/dev/nvme2n1

create_mock_nvme_devices() {
    DIR="$1"
    local count=$2

    mkdir -p "$DIR/dev"

    for ((i=0; i<count; i++)); do
        # Create block device files (touch creates regular files, but for testing purposes this works)
        touch "$DIR/dev/nvme${i}n1"
    done
}

@test "Empty temp directory" {
    TEST_DEV_DIR=$(mktemp -d)

    result=$(get_device_count "$TEST_DEV_DIR")
    [ "$result" == "0" ]

    rm -rf "$TEST_DEV_DIR"
}

@test "Temp Directory with fake devices" {
    TEST_DEV_DIR=$(mktemp -d)
    create_mock_nvme_devices $TEST_DEV_DIR 3

    result=$(get_device_count "$TEST_DEV_DIR/dev")
    [ "$result" == "3" ]

    rm -rf "$TEST_DEV_DIR"
}

@test "Check NVMe count with no expected value" {
    TEST_DEV_DIR=$(mktemp -d)
    create_mock_nvme_devices $TEST_DEV_DIR 2

    run check_nvme_count
    [ "$status" -eq 1 ]
    [[ "$output" == *"No expected value provided"* ]]

    rm -rf "$TEST_DEV_DIR"
}