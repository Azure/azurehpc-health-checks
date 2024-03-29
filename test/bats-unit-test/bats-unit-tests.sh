#!/usr/bin/env bats

NHC_DIR=$AZ_NHC_ROOT
logpath=/tmp/nhclogfile.log

if [ -z "$NHC_DIR" ]; then
   NHC_DIR=/opt/azurehpc/test/azurehpc-health-checks/
fi

NHC_PATH=$NHC_DIR/run-health-checks.sh

get_sad_path_conf(){
    SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")
    SKU="${SKU,,}"
    if echo "$SKU" | grep -q "nd96asr_v4"; then
        conf_name="nd96asr_v4"
    elif echo "$SKU" | grep -q "nd96amsr_a100_v4"; then
        conf_name="nd96amsr_a100_v4"
    elif echo "$SKU" | grep -q "nd96isr_h100_v5"; then
        conf_name="nd96isr_h100_v5"
    elif echo "$SKU" | grep -q "hb176rs_v4"; then
        conf_name="hb176rs_v4"
    elif echo "$SKU" | grep -q "hx176rs"; then
        conf_name="hx176rs"
    else
        echo "Unit-test for this SKU $SKU is not supported" 
        return 1
    fi
    relative_path="$NHC_DIR/test/bad_test_confs/$conf_name.conf"
    echo "$(realpath -m $relative_path)"
    return 0
}

@test "Installation check" {
    set +e
    command -v  nhc
    result=$?
    set -e
    [ "$result" -eq 0 ]
}

@test "Default checks Pass (Happy Path)" {   
    sudo $NHC_PATH -o $logpath
    result=$?
    [ "$result" -eq 0 ]
}

@test "Checks adjusted to fail (Sad Path)" {
    bad_conf_file=$(get_sad_path_conf)
    if [[ "$bad_conf_file" == *"not supported"* ]]; then
        return false
    fi
    set +e
    out=$(sudo $NHC_PATH -c $bad_conf_file -o $logpath)
    result=$?
    set -e
    [ "$result" -ne 0 ]
}
