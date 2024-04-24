#!/usr/bin/env bats


logpath=/tmp/nhclogfile.log
NHC_PATH=$NHC_DIR/run-health-checks.sh
source $NHC_DIR/test/unit-tests/nhc-test-common.sh

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
    set -e
    echo "$out" | grep -q "ERROR"
    result=$?
    [ "$result" -eq 0 ]
}
