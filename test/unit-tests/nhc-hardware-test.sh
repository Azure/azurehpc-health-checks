#!/usr/bin/env bats

source $AZ_NHC_ROOT/customTests/azure_common.nhc
source $AZ_NHC_ROOT/test/unit-tests/nhc-test-common.sh

hardware_test=( "azure_nvme_count.nhc" )

for check in "${hardware_test[@]}" ; do
    source $AZ_NHC_ROOT/customTests/$check
done

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