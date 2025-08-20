#!/usr/bin/env bats

source $NHC_DIR/customTests/azure_common.nhc
source $NHC_DIR/test/unit-tests/nhc-test-common.sh

azure_ib_link_flapping_test=( "azure_ib_link_flapping.nhc" )
 
for check in "${azure_ib_link_flapping_test[@]}" ; do
    source $NHC_DIR/customTests/$check
done

#Invalid File Input
@test "Check Invalid File Input" {
    fakeFile="filedoesnotexist"
    run check_ib_link_flapping 1 1 "$fakeFile"

    echo $output
    # Check that the file does not exist
    [[ "$output" == *"Warning - log file filedoesnotexist not found, skipping"* ]]
    # Check that the check is not ran
    [[ "$output" == *"IB Link flapping test skipped."* ]]
}

# Valid File with no link flaps
@test "Check Valid File Input" {
    filePath="$NHC_DIR/test/data/1dev_6flap_syslog"
    lookback=24
    threshold=1
    run check_ib_link_flapping $lookback $threshold "$filePath"
    
    echo $output

    [[ "$output" == *"Checking log files: "*"$filePath"* ]]
    [[ "$output" == *"No IB devices exceeded link flap threshold ($threshold) in the last $lookback hours"* ]]
}  

@test "Check IB Device Count - 1 Device 6 Flaps" {
    filePath="$NHC_DIR/test/data/1dev_6flap_syslog"
    lookback=24
    threshold=1

    now=$(date -d "2025-08-18 00:00:00" +%s)
    start_time=$((now - (lookback * 3600)))

    echo $now 
    echo $start_time

    get_linkflap_count "$filePath" "$start_time" "$now"

    echo "Awk file inputs " $awk_file_counts
    
    # Check 6 were detected for ib6
    [[ "$awk_file_counts" == *"6 ib6"* ]]
}

@test "Check IB Device Count - 1 Device 6 Flaps Small Lookback" {
    filePath="$NHC_DIR/test/data/1dev_6flap_syslog"
    lookback=1
    threshold=1

    now=$(date -d "2025-08-19 00:00:00" +%s)
    start_time=$((now - (lookback * 3600)))

    echo $now 
    echo $start_time

    get_linkflap_count "$filePath" "$start_time" "$now"

    echo "Awk file inputs " $awk_file_counts

    # Check that no link flaps were detected
    [[ "$awk_file_counts" == *""* ]]
}

@test "Check IB Device Count - 0 Flaps Standard Lookback" {
    filePath="$NHC_DIR/test/data/1dev_6flap_syslog"
    lookback=24
    threshold=1

    now=$(date -d "2025-08-19 00:00:00" +%s)
    start_time=$((now - (lookback * 3600)))

    echo $now 
    echo $start_time

    get_linkflap_count "$filePath" "$start_time" "$now"

    echo "Awk file inputs " $awk_file_counts

    # Check that no link flaps were detected
    [[ "$awk_file_counts" == *""* ]]
}

