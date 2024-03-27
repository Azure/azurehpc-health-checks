#!/usr/bin/env bats

source $AZ_NHC_ROOT/customTests/azure_common.nhc
source $AZ_NHC_ROOT/test/unit-tests/nhc-test-common.sh



gpu_test=( "azure_gpu_count.nhc" "azure_gpu_bandwidth.nhc" "azure_gpu_ecc.nhc" "azure_nccl_allreduce.nhc" "azure_ib_write_bw_gdr.nhc" "azure_ib_write_bw_non_gdr.nhc")


for check in "${gpu_test[@]}" ; do
    source $AZ_NHC_ROOT/customTests/$check
done

@test "Pass case: check_gpu_count" {
    set +e
    gpu_count=$(nvidia-smi --list-gpus | wc -l)
    result=$(check_gpu_count $gpu_count)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_gpu_count" {
    set +e
    result=$(check_gpu_count 10)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_gpu_bw" {
    set +e
    result=$(check_gpu_bw 1 1)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_gpu_bw" {
    set +e
    result=$(check_gpu_bw 500 500)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_gpu_ecc" {
    if lspci | grep -i 'VGA\|3D controller'| grep -qi 'V100'; then
        echo "Skipping normal check_gpu_ecc for V100 SKU. ECC addressed in SDB unit test"
    else
        set +e
        result=$(check_gpu_ecc 30000000 30000000)
        status=$?
        set -e
        [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
    fi
}

@test "Fail case: check_gpu_ecc" {
    if lspci | grep -i 'VGA\|3D controller'| grep -qi 'V100'; then
        echo "Skipping normal check_gpu_ecc for V100 SKU. ECC addressed in SDB unit test"
    else
        set +e
        result=$(check_gpu_ecc -1 -1)
        echo $result
        set -e
        [[ "$result" == *"ERROR"* ]]
    fi
}

@test "Pass case: check_nccl_allreduce" {
    set +e
    topo_file=$(get_topofile)
    result=$(check_nccl_allreduce 1.0 1 $topo_file 8G)
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_nccl_allreduce" {
    set +e
    topo_file=$(get_topofile)
    result=$(check_nccl_allreduce 600.0 1 $topo_file 8G)
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Pass case: check_ib_bw" {
    set +e
    ib_type=$(get_ib_type)
    if [[ $ib_type == "gdr" ]]; then
        result=$(check_ib_bw_gdr 1.0)
    elif [[ $ib_type == "non_gdr" ]]; then
        result=$(check_ib_bw_non_gdr 1.0)
    else
        # no IB test, set to passing case
        result="PASS"
    fi
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [[ $status -eq 0 ]]
}

@test "Fail case: check_ib_bw" {
    set +e
    ib_type=$(get_ib_type)
    if [[ $ib_type == "gdr" ]]; then
        result=$(check_ib_bw_gdr 1000.0)
    elif [[ $ib_type == "non_gdr" ]]; then
        result=$(check_ib_bw_non_gdr 1000.0)
    else
        # no IB test, set to passing case
        result="ERROR"
    fi
    set -e
    [[ "$result" == *"ERROR"* ]]
}

@test "Check Collect_ecc_data function" {
    set +e
    result=$(collect_ecc_data "SDBE")
    status=$?
    set -e
    [[ "$result" != *"ERROR"* ]] && [ "$status" -eq 0 ]
}

@test "Check SDBE_ecc function" {
    # only v100 SKU
    if lspci | grep -i 'VGA\|3D controller'| grep -qi 'V100'; then
        set +e
        result=$(check_SDBE_ecc)
        status=$?
        set -e
        [[ "$result" != *"ERROR"* ]] && [ "$status" -eq 0 ]
    else
        echo "No V100 GPU found, skipping test"
    fi
}

@test "Check Page Retirement Table Full error" {
    IFS=$'\n'
    TAB=$'\t'
    gpu_sections=($(awk '/GPU / {print $NF}' $AZ_NHC_ROOT/test/data/bad_nvsmi8_output.txt))
    sbe_sections=($(awk '/Single Bit ECC / {print $NF}' $AZ_NHC_ROOT/test/data/bad_nvsmi8_output.txt))
    dbe_sections=($(awk '/Double Bit ECC / {print $NF}' $AZ_NHC_ROOT/test/data/bad_nvsmi8_output.txt))
    ppending_blacklist_sections=($(awk '/Pending Page Blacklist / {print $NF}' $AZ_NHC_ROOT/test/data/bad_nvsmi8_output.txt))
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
