#! /bin/bash

function collect_meta_data(){
    # get meta data for VM and underlying host
    vmhostname=$(hostname)
    vmid=$( curl -H Metadata:true --max-time 10 -s  "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-03-01&format=text")
    vmname=$(curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-11-15&format=text")
    kernelVersion=$(uname -r)
}


if [ -z "$AZ_NHC_ROOT" ]; then
    AZ_NHC_ROOT="/azure-nhc"
fi

CONF_FILE=${AZ_NHC_ROOT}/conf/aznhc.conf
OUTPUT_PATH=${AZ_NHC_ROOT}/output/aznhc.log
DEFAULT_NHC_FILE_PATH=${AZ_NHC_ROOT}/default


# Check if the output file exists, if not create it
if [ ! -f $OUTPUT_PATH ]; then
    touch $OUTPUT_PATH
    output_mounted=false
fi

#------------------Collect VM Meta Data-------------------
# This clause is only for cases where the docker image is used without the run script
# The run script will use the string "VM Meta Data" so if it is present we skip this section
if ! grep -q "VM Meta Data" "$OUTPUT_PATH"; then
    # Obtain Node Name MetaData
    collect_meta_data
    # Add meta Data to log output file
    cat <<EOF >> $OUTPUT_PATH
    ------ VM Meta Data ------
    VM NAME: $vmname
    VM HOST NAME: $vmhostname
    VM ID: $vmid
    Kernel Version: $kernelVersion
EOF
fi

# Set default time out if ENV variable not present
if [ -z "$TIMEOUT" ]; then
    TIMEOUT=500
fi

#------------------Default conf file set up-------------------
if [ ! -f $CONF_FILE ]; then
    echo "No custom conf file specified, detecting VM SKU..."
    SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text" | tr '[:upper:]' '[:lower:]' | sed 's/standard_//')
    CONF_DIR="$DEFAULT_NHC_FILE_PATH/conf"
    CONF_FILE="$CONF_DIR/$SKU.conf"

    if [ -f "$CONF_FILE" ]; then
        echo "Running health checks for Standard_$SKU SKU..."
    else
        echo "The vm SKU 'standard_$SKU' is currently not supported by Azure health checks." | tee -a $OUTPUT_PATH
        return 1
    fi
fi

#---------------------------------------------

# Check if we mounted Custom test directory. If so update the custom tests.
if [ -d "${AZ_NHC_ROOT}/customTests/" ]; then
    cp ${AZ_NHC_ROOT}/customTests/*.nhc /etc/nhc/scripts/
fi

# Run nhc
if [ "${#NHC_ARGS[@]}" -eq 0 ]; then
    nhc CONFFILE=$CONF_FILE LOGFILE=$OUTPUT_PATH TIMEOUT=$TIMEOUT
else
    nhc ${NHC_ARGS[@]} CONFFILE=$CONF_FILE LOGFILE=$OUTPUT_PATH TIMEOUT=$TIMEOUT
fi
nhc_exit_code=$?

if [ "$output_mounted" = false ]; then
    cat $OUTPUT_PATH
fi

echo "Health checks completed with exit code: ${nhc_exit_code}." | tee -a $OUTPUT_PATH

exit $nhc_exit_code
