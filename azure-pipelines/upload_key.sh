#!/bin/bash

####
# @Brief        : Function to report errors
# @Param        : (1) #Error code
#                 (2) #Error message
# @RetVal       : null
####
report_error(){
    error_code=$1
    error_message=$2

    cat <<EOF > error_info.json
    {
        "Code": "${error_code}",
        "Message": "${error_message}",
        "Timestamp": "$(date -u +%a,\ %d\ %b\ %Y\ %H:%M:%S\ GMT)"
    }
EOF
    
    echo "##[error]${error_message}"
    echo "Pushing error information onto log analytics container"
    bash tologanalytics.sh "${LOG_ANALYTICS_CONTAINER}" "error_info.json"
    exit ${error_code}
}

####
# @Brief        : Function to run an az command
# @Param        : command string
# @RetVal       : output of command
####
run_command(){
    command_string=$1
    echo "##[command]${command_string}"
    output=$(eval ${command_string} 2>&1) || { report_error "$?" "$output"; }
    echo "$output"
}

####
# @Brief        : Generate ssh key pair
# @Param        : null
# @RetVal       : null
####
generate_keys(){
    # Create ssh key pair
	echo "##[section]Creating SSH key pair"
	ssh-keygen -t rsa -b 4096 -C "${USERNAME}@azurehpc" -N "" -f ~/.ssh/id_rsa <<< y

    echo "##[debug]Private key:"
    ls ~/.ssh
    cat ~/.ssh/id_rsa
}

####
# @Brief        : Upload private key onto storage container
# @Param        : null
# @RetVal       : null
####
upload_key(){
    generate_keys

    container_name="keys"
    destination_blob="private-key"

    echo "##[section]Creating Container with Storage Account"
    command_string="az storage container create \
        --name ${container_name} \
        --account-name ${STORAGE_ACC_NAME}"
    run_command "${command_string}"

    echo "##[section]Uploading private key file onto the destination blob"
    command_string="az storage blob upload \
        --container-name ${container_name} \
        --file ~/.ssh/id_rsa \
        --account-name ${STORAGE_ACC_NAME} \
        --name ${destination_blob}"
    run_command "${command_string}"
}

# 1ES hosted agents although being stateful may cause 2 kinds of job failures
#   1. VM recycle duration expiry - causing agents to purge
#       - This forces 1ES spawn new agents which won't have VM access
#   2. Sometimes stateless agents are spawned 
#       - These agents won't have a permanent storage and thus no access to the VMs

# Proposed Workaround
# Store the private key used in creating VMs and then use the same when accessing VMs
# This ensures integrity for agents to have access to the VMs/ scalesets irrespective of their state

# Upload the private key
upload_key

# Alternative workaroud
# Set password based authentication to the VMs/ Scalesets
# Caution: Doesn't guarantee total integrity