#!/bin/bash

source $(dirname "${BASH_SOURCE[0]}")/basic_tests.sh


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
    relative_path="$(dirname "${BASH_SOURCE[0]}")/../bad_test_confs/$conf_name.conf"
    echo "$(realpath -m $relative_path)"
    return 0
}


#happy path
happy_path(){
    echo "Running  ${FUNCNAME[0]} test"
    EXPECTED_CODE=0
    runtest $EXPECTED_CODE
    result=$?

    if [ "$result" -eq $EXPECTED_CODE ]; then
        echo "${FUNCNAME[0]} test: Passed"
        return 0
    else
        echo "${FUNCNAME[0]} test: Failed"
        return 1
    fi
}

#sad path
sad_path(){
    echo "Running  ${FUNCNAME[0]} test"
    bad_conf_file=$(get_sad_path_conf)
    if [[ "$bad_conf_file" == *"not supported"* ]]; then
        echo "${FUNCNAME[0]} test: Failed"
        return 1
    fi
    EXPECTED_CODE=1
    runtest $EXPECTED_CODE "$bad_conf_file"
    result=$?
    echo $result
    if [ "$result" -eq $EXPECTED_CODE ]; then
        echo "${FUNCNAME[0]} test: Passed"
        return 0
    else
        echo "${FUNCNAME[0]} test: Failed"
        return 1
    fi
}

happy_path
sad_path