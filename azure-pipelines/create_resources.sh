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
# @Brief        : Function to create storage account - temporary resource
# @Param        : Resource Group Name
# @RetVal       : null
####
create_storage_account(){
    # Create a storage account that is used for the following
    #   1. Downloading the VHD
    #   2. Storing the private key information

    # Storage account is created as a non reusable resource for the following reasons:
    #   1. To associate resource to pipeline run rather than RG
    #   2. To allow rerun of failed jobs without rewriting private-key

    resource_grp_name=$1
    storage_acc_name=$2

    # Create a Storage Account
    echo "##[section]Creating Storage Account"
    echo "##[debug]Storage Account Name: ${storage_acc_name}"
    
    command_string="az storage account create \
        --name ${storage_acc_name} \
        --resource-group ${resource_grp_name} \
        --sku Standard_LRS"
    run_command "${command_string}"
}

####
# @Brief        : Create all the common resources used in pipeline
# @Param        : null
# @RetVal       : null
####
create_resources(){
    # Check if the resource group already exists in the subscription
    # if it does, clean it before the pipeline run
    echo "##[section]Checking if Resource Group already exists"
    command_string="az group exists -n ${RESOURCE_GRP_NAME}"
    run_command "${command_string}"
    rg_exists=$output
    echo "##[debug]RG Exists: ${rg_exists}"
    if $rg_exists; then bash ./run_cleanup.sh; sleep 900; fi

    # Create a resource group to hold all the resources
    echo "##[section]Creating Resource Group"
    command_string="az group create \
        --location ${RESOURCE_GRP_LOCATION} \
        --name ${RESOURCE_GRP_NAME} \
        --tags owner=rameht@microsoft.com"
    run_command "${command_string}"
    
    # Create availability set
    # The availability sets are hardware dependent
    # Reference: https://docs.microsoft.com/en-us/archive/blogs/shwetanayak/learnings-azure-availability-sets
    echo "##[group]Creating Availability Sets for different hardware types"
    echo "##[section]Creating availability set for ND Series"
    command_string="az vm availability-set create \
        --name hpcval-avset-${GPU_SIZE_OPTION} \
        --resource-group ${RESOURCE_GRP_NAME}"
    run_command "${command_string}"
    
    echo "##[section]Creating availability set for HB Series"
    command_string="az vm availability-set create \
        --name hpcval-avset-${HPC_SIZE_OPTION} \
        --resource-group ${RESOURCE_GRP_NAME}"
    run_command "${command_string}"
    echo "##[endgroup]"

    # echo "##[section]Creating a Virtual Network for resources"
    # command_string="az network vnet create \
    #     --resource-group ${RESOURCE_GRP_NAME} \
    #     --name ${VNET_NAME} \
    #     --address-prefix 10.0.0.0/16 \
    #     --subnet-name default \
    #     --subnet-prefix 10.0.0.0/24"
    # run_command "${command_string}"

    # The image creation pipeline can create images at varied location
    # if RG is not in WUS2 then create another temporary local gallery
    # To sync the images accross regions with AzHPCImageGallery
    # Create the Shared image gallery (only when an image is requested) to hold the image definitions
    if [ "${RESOURCE_GRP_LOCATION}" != "westus2" ] && \
        [ "${BUILD_TYPE}" != "None" ] && \
        { [ "${CREATE_UBUNTU-HPC_22_04}" = True ] || \
            [ "${CREATE_UBUNTU_20_04}" = True ] || \
            [ "${CREATE_UBUNTU_18_04}" = True ] || \
            [ "${CREATE_CENTOS_7_9}" = True ] || \
            [ "${CREATE_ALMA_8_7}" = True ]; }
    then
        command_string="az sig create \
            --resource-group ${RESOURCE_GRP_NAME} \
            --gallery-name HPCImageGallery"
        run_command "${command_string}"
    fi
}


####
# @Brief        : Perform VNET peering between 1ES hosted agents and RG from pipeline run
# @RetVal       : null
####
peer_vnets(){
    echo "##[warning] Resetting/ Establishing new peering between VNETs."
    command_string="az resource update \
        --name ${AGENT_POOL} \
        --resource-group 1ES-hosted-pool \
        --resource-type Microsoft.CloudTest/hostedpools \
        --set properties.networkProfile.peeredVirtualNetworkResourceId=''"
    run_command "${command_string}"

    command_string="az network vnet show \
        --resource-group ${RESOURCE_GRP_NAME} \
        --name ${VNET_NAME}"
    run_command "${command_string}"
    vnet_id=$(echo "$output" | jq -r '.id')
    echo "##[debug]VNET ID: ${vnet_id}"
    
    command_string="az resource update \
        --name ${AGENT_POOL} \
        --resource-group 1ES-hosted-pool \
        --resource-type Microsoft.CloudTest/hostedpools \
        --set properties.networkProfile.peeredVirtualNetworkResourceId=${vnet_id}"
    run_command "${command_string}"

    command_string="az network vnet peering update \
        --name ${VNET_NAME}-${AGENT_POOL}-vnet \
        --resource-group ${RESOURCE_GRP_NAME} \
        --vnet-name ${VNET_NAME} \
        --set allowVirtualNetworkAccess=true \
        --set allowForwardedTraffic=true"
    run_command "${command_string}"
    echo "VNETs Connected!"
}

####
# @Brief        : Function to create SDOStdPolicyNetwork policy exemption
# @Param        : Resource Group Name
# @RetVal       : null
####
create_exemption(){
    resource_grp_name=$1
    
    # Create policy exemption
    echo "##[section]Adding policy exemption for resource group"
    command_string="az policy exemption create \
        --name imageValidationSDOStdPolicyNetworkExemption \
        --display-name 'ImageValidationRG - SDOStdPolicyNetwork' \
        --exemption-category 'Waiver' \
        --policy-assignment '/subscriptions/d71c7216-6409-45f8-be15-35cf57b8527c/providers/Microsoft.Authorization/policyAssignments/SDOStdPolicyNetwork' \
        --resource-group ${resource_grp_name}"
    run_command "${command_string}"
}

# Create all the common resources used in pipeline
create_resources

# Create exemption for hpcperf1 subscription policy
if [ ${SERVICE_CONNECTION} == "hpcperf1_ServiceConn" ]
then
  create_exemption ${RESOURCE_GRP_NAME}
fi

# Create a storage account - a temporary non reusable resource
create_storage_account ${RESOURCE_GRP_NAME} ${STORAGE_ACC_NAME}

# Perform VNET peering to allow 1ES-agents access to resources
# peer_vnets
