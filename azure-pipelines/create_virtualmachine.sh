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
    output=$(eval ${command_string} 2>null) || { report_error "$?" "$output"; }
    echo "$output"
}

####
# @Brief        : Get Vanilla Image URI
# @Param        : OS Type
# @RetVal       : Vanilla Image URI
####
get_hpc_image_uri() {
	case $1 in
		ubuntu-hpc_22.04) echo microsoft-dsvm:ubuntu-hpc:2204:latest;;
		*) echo Unknown OS; exit 1;;
	esac
}

####
# @Brief        : Get appropriate size for VM
# @Param        : OS Type
# @RetVal       : Vm Size (String)
####
size_for_os() {
	case $1 in
		ubuntu* | centos7.9 | alma8.7) echo "$GPU_SIZE_OPTION";;
		centos[7-8].[1-8]) echo "$HPC_SIZE_OPTION";;
		*) echo Unknown OS; exit 1;;
	esac
}

####
# @Brief        : Check if the VM is already existing
# @Param        : null
# @RetVal       : null
####
create_virtual_machine(){
	# Delete the VM if it is already existing
	# Also, to accommodate job retry on VMs in case of failure
	echo "##[section]Checking if the Virtual Machine already exists"
	if [[ $(az vm list --resource-group "${RESOURCE_GRP_NAME}" --query "[?name=='hpcvalvm-$os'] | length(@)") > 0 ]]
	then 
		echo "##[warning]VM already exists. Deleting and recreating it."
		command_string="az vm delete \
			--name "hpcvalvm-$os" \
			--resource-group ${RESOURCE_GRP_NAME} \
			--yes"
		run_command "${command_string}"
		sleep 60
	else
		echo "VM doesn't exist"
	fi

	sku=$(size_for_os "$os")
	avset="hpcval-avset-${sku}"

	# Set the subscription ID to reference the VNET
	if [ ${SERVICE_CONNECTION} == "HPCScrub1_ServiceConn" ]
	then
		sub_id="d2c9544f-4329-4642-b73d-020e7fef844f"
	else
		sub_id="d71c7216-6409-45f8-be15-35cf57b8527c"
	fi

	subnet_id="/subscriptions/${sub_id}/resourceGroups/1ES-peered-vnets/providers/Microsoft.Network/virtualNetworks/${RESOURCE_GRP_LOCATION}-vnet/subnets/default"
	
	echo "##[section]Creating the Virtual Machine for $os"
	command_string="az vm create \
		--name hpcvalvm-$os \
		--resource-group ${RESOURCE_GRP_NAME} \
		--size $sku \
		--admin-username ${USERNAME} \
		--accelerated-networking ${ACCL_NW} \
		--ssh-key-values ~/.ssh/id_rsa.pub \
		--subnet ${subnet_id} \
		--availability-set ${avset} \
		--image $(get_hpc_image_uri $os) \
		$(if [ $os == "alma8.7" ]; then echo "--plan-name 8-gen2 --plan-product almalinux --plan-publisher almalinux"; fi) \
		--tags SkipASMAzSecPack=true SkipASMAV=true SkipLinuxAzSecPack=true \
		--only-show-errors"
	run_command "${command_string}"
	VM_IP=$(echo "$output" | jq -r '.privateIpAddress')
	echo "##[debug]VM IP address: ${VM_IP}"

	host_name="${USERNAME}@${VM_IP}"
	echo "##[debug]Host Name: $host_name"
	echo "##vso[task.setvariable variable=hostnameOutput;isOutput=true]$host_name"

	# Delete the OMS agent VM extension to avoid the OMS logging service
	echo "##[section]Deleting the OMS Agent for Linux VM extension"
	command_string="az vm extension delete \
		--resource-group ${RESOURCE_GRP_NAME} \
		--vm-name hpcvalvm-$os \
		--name OmsAgentForLinux"
	run_command "${command_string}"

	sleep 60
	
	echo "##[section] Checking connection to the VM"
	retry_count=0
	ssh -o StrictHostKeyChecking=no "$host_name" 'echo "Reachable!"'
	# Retrying the command in case of failure for 5 times
	while [ $? -ne 0 ] && (( retry_count++ < 5 ))
	do
		sleep 60 & wait $!
		ssh -o StrictHostKeyChecking=no "$host_name" 'echo "Reachable!"'
	done

	echo "##[section]Setting SSH configuration"
	ssh-keyscan -t rsa -H ${VM_IP} >> ~/.ssh/known_hosts
	# Add public key to authorized users for debug purposes
	echo ${PUBLIC_KEY} | ssh "$host_name" 'cat >> /home/hpcuser/.ssh/authorized_keys'
}

# Parameter OS flavour
os=$1

# Create the VM for HPC specialization
create_virtual_machine
