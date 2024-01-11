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
# @Brief        : Delete resources used in image creation pipeline
# @Param        : null
# @RetVal       : null
####
delete_resources(){
	echo "##[warning]Deleting Resource group"
	command_string="az group delete \
		--name ${RESOURCE_GRP_NAME} \
		--yes \
		--no-wait"
	run_command "${command_string}"
	echo "${RESOURCE_GRP_NAME} deleted!"

	# echo "##[warning]Removing VNET peering"
	# command_string="az resource update \
	# 	--name ${AGENT_POOL} \
	# 	--resource-group 1ES-hosted-pool \
	# 	--resource-type Microsoft.CloudTest/hostedpools \
	# 	--set properties.networkProfile.peeredVirtualNetworkResourceId=''"
	# run_command "${command_string}"
	
	# command_string="az network vnet peering delete \
	# 	--resource-group 1ES-hosted-pool \
	# 	--name ${AGENT_POOL}-vnet-${VNET_NAME} \
	# 	--vnet-name ${AGENT_POOL}-vnet"
	# run_command "${command_string}"
	
	# echo "VNET peering removed"
}

# Delete the resources used for Image creation pipeline
delete_resources
