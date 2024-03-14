#!/usr/bin/env bats
aznhc_root=$(dirname "$(dirname "$(pwd)")")
test_root=$(dirname "$(pwd)")

source $aznhc_root/customTests/azure_common.nhc
source $aznhc_root/test/unit-tests/nhc-test-common.sh

# Load HPC-X
hpcx_init_file=$(find /opt/hpcx* -maxdepth 1 -name "hpcx-init.sh")
source $hpcx_init_file
hpcx_load

gpu_test="azure_gpu_ecc.nhc"
source $aznhc_root/customTests/$gpu_test

@test "Check Collect_ecc_data function" {
    set +e
    result=$(collect_ecc_data "SDBE")
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [ "$status" -eq 0 ]
}

@test "Check SDBE_ecc function" {
    set +e
    result=$(check_SDBE_ecc)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [ "$status" -eq 0 ]
}

IFS=$'\n'
TAB=$'\t'
gpu_sections=($(awk '/GPU / {print $NF}' $test_root/data/bad_nvsmi8_output.txt))
sbe_sections=($(awk '/Single Bit ECC / {print $NF}' $test_root/data/bad_nvsmi8_output.txt))
dbe_sections=($(awk '/Double Bit ECC / {print $NF}' $test_root/data/bad_nvsmi8_output.txt))
ppending_blacklist_sections=($(awk '/Pending Page Blacklist / {print $NF}' $test_root/data/bad_nvsmi8_output.txt))

@test "Check Page Retirement Table Full error" {
    set +e
    flag="false"
    error_msg=''
    for i in "${!gpu_sections[@]}"; do
        # Extract SBE and DBE values
        gpu=${gpu_sections[i]}
        sbe=${sbe_sections[i]}
        dbe=${dbe_sections[i]}

        # Calculate the sum of SBE and DBE pages
        total=$((sbe + dbe))

        #implement page retirement check
        # Check if page blacklist is pending
        pending=${ppending_blacklist_sections[i]}
        
        if [ "$total" -ge 62 ] && [ "$pending" == "Yes" ]; then
            echo "error: Retirement Table Full for, GPU: $gpu, Total Pages: $total, Pending Blacklist: $pending"
            flag="true"
            error_msg+="$TAB error: Retirement Table Full for, GPU: $gpu, Total Pages: $total, Pending Blacklist: $pending$IFS"
        fi
    done

    if [ "$flag" == "true" ]; then
        echo "ERROR: $IFS$error_msg"
    fi

    status=$?
    set -e
    [ "$status" -eq 0 ]
}
