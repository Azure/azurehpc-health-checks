#!/usr/bin/env bash
#
# aznhc-entrypoint.sh
# A host-based entrypoint script for running Azure NHC checks on Ubuntu 22.04.

# Function to collect meta data for VM and underlying host
function collect_meta_data(){
    vmhostname=$(hostname)
    vmid=$( curl -H Metadata:true --max-time 10 -s  "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-03-01&format=text")
    vmname=$(curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-11-15&format=text")
    kernelVersion=$(uname -r)
}

# The root directory for the NHC files. If not set externally, default to /azure-nhc.
if [ -z "$AZ_NHC_ROOT" ]; then
    AZ_NHC_ROOT="/azure-nhc"
fi

# Default paths (if environment variables are not set)
# Note: The first script typically sets these. If not set, we fall back to defaults here.
if [ -z "$AZ_NHC_CONF_FILE" ]; then
    CONF_FILE="${AZ_NHC_ROOT}/conf/aznhc.conf"
else
    CONF_FILE="$AZ_NHC_CONF_FILE"
fi

if [ -z "$AZ_NHC_OUTPUT_FILE" ]; then
    OUTPUT_PATH="${AZ_NHC_ROOT}/output/aznhc.log"
else
    OUTPUT_PATH="$AZ_NHC_OUTPUT_FILE"
fi

if [ -z "$AZ_NHC_SYSLOG_FILE" ]; then
    # Possibly /var/log/syslog or /var/log/messages
    # But if not set, we don't forcibly break. We'll just continue without it.
    KERNEL_LOG=""
else
    KERNEL_LOG="$AZ_NHC_SYSLOG_FILE"
fi

DEFAULT_NHC_FILE_PATH="${AZ_NHC_ROOT}/default"

# If user didn't set TIMEOUT, default to 500
if [ -z "$TIMEOUT" ]; then
    TIMEOUT=500
fi

# If user didn't set NHC_ARGS, treat as empty
if [ -z "$NHC_ARGS" ]; then
    NHC_ARGS=()
else
    # If it's a string, convert to array
    # For example: NHC_ARGS="-v -d" => array
    # If you are passing in multiple flags as a single string, we can parse them:
    # read -ra NHC_ARGS <<< "$NHC_ARGS"
    # But if you’re passing them in as an array already, this step might be skipped.
    :
fi

# Ensure the output file exists
if [ ! -f "$OUTPUT_PATH" ]; then
    mkdir -p "$(dirname "$OUTPUT_PATH")" 2>/dev/null
    touch "$OUTPUT_PATH"
    output_mounted=false
else
    output_mounted=true
fi

# Collect metadata only if the log file does not already have the "VM Meta Data" marker
if ! grep -q "VM Meta Data" "$OUTPUT_PATH"; then
    collect_meta_data
    cat <<EOF >> "$OUTPUT_PATH"
------ VM Meta Data ------
VM NAME: $vmname
VM HOST NAME: $vmhostname
VM ID: $vmid
Kernel Version: $kernelVersion
EOF
fi

# If the user has not supplied a conf file, try to auto-detect the SKU
if [ ! -f "$CONF_FILE" ]; then
    echo "No custom conf file found. Attempting to detect VM SKU..." | tee -a "$OUTPUT_PATH"
    SKU=$(curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text" \
        | tr '[:upper:]' '[:lower:]' \
        | sed 's/standard_//')

    CONF_DIR="${DEFAULT_NHC_FILE_PATH}/conf"
    CONF_FILE="${CONF_DIR}/${SKU}.conf"

    if [ -f "$CONF_FILE" ]; then
        echo "Running health checks for Standard_${SKU} SKU..." | tee -a "$OUTPUT_PATH"
    else
        echo "The VM SKU 'standard_${SKU}' is currently not supported by Azure health checks." | tee -a "$OUTPUT_PATH"
        exit 1
    fi
fi

# If a customTests folder is present, copy scripts to /etc/nhc/scripts
if [ -d "${AZ_NHC_ROOT}/customTests/" ]; then
    sudo mkdir -p /etc/nhc/scripts/
    sudo cp "${AZ_NHC_ROOT}"/customTests/*.nhc /etc/nhc/scripts/ 2>/dev/null
fi

# Run the NHC checks
echo "Running NHC with config: $CONF_FILE" | tee -a "$OUTPUT_PATH"
echo "NHC_ARGS: ${NHC_ARGS[@]}" | tee -a "$OUTPUT_PATH"

if [ "${#NHC_ARGS[@]}" -eq 0 ]; then
    nhc CONFFILE="$CONF_FILE" LOGFILE="$OUTPUT_PATH" TIMEOUT="$TIMEOUT"
else
    nhc "${NHC_ARGS[@]}" CONFFILE="$CONF_FILE" LOGFILE="$OUTPUT_PATH" TIMEOUT="$TIMEOUT"
fi
nhc_exit_code=$?

# If the output file wasn't previously present (i.e., not host-mounted), print it
if [ "$output_mounted" = false ]; then
    cat "$OUTPUT_PATH"
fi

echo "Health checks completed with exit code: ${nhc_exit_code}." | tee -a "$OUTPUT_PATH"
exit $nhc_exit_code
