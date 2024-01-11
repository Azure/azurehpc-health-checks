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
# @Brief        : Download private key to allow stateless agents access to VMs
# @Param        : null
# @RetVal       : null
####
download_key(){
    # Delete known_hosts file
    rm -f ~/.ssh/known_hosts

    private_key_file=~/private_key.txt
    if [ ! -f "${private_key_file}" ]
    then
        echo "##[section]Downloading private key"
        command_string="az storage blob download \
            --account-name ${STORAGE_ACC_NAME} \
            --container-name keys \
            --name private-key \
            --file ${private_key_file}"
        run_command "${command_string}"

        # Check if the headnode is created and if so, acknowledge it using new stateless agent
        if [ ! -z ${HEADNODE_IP} ]
        then
            echo "Acknowledging headnode"
            ssh-keyscan -t rsa -H ${HEADNODE_IP} >> ~/.ssh/known_hosts
        fi

        # Permissions 0666 for '~/private_key.txt' are too open
        # Change the permissions to read-only
        echo "Setting appropriate permissions to the private key file"
        chmod 400 ${private_key_file}
    else
        echo "##[warning]Private key already exists!"
    fi

    echo "##vso[task.setvariable variable=private_key_file]$private_key_file"    
}

# This is run in the jobs that have headnode interference
# To allow stateless agents to gain access to the VMSS
download_key
