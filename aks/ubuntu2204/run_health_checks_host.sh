#!/bin/bash
# This script runs GPU node health checks directly on the host (Ubuntu 22.04)
# It replicates the functionality of the Docker-based version but without containerization.

# Set the root directory to the location of this script.
#AZ_NHC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AZ_NHC_ROOT="/azurehpc-health-checks":
WORKING_DIR="$AZ_NHC_ROOT"  # In host mode, our working directory is the same as the root

# Default values for arguments
CONF_FILE=""
OUTPUT_PATH="./health.log"
TIMEOUT=500
VERBOSE=false
RUN_ALL=false
APPEND_CONF_PATH=""
USER_DIRS=""

# Print help information
function print_help() {
cat << EOF

Usage: $0 [-h|--help] [-c|--config <path to an NHC .conf file>] [-o|--output <directory path for log files>] [-e|--append_conf <path to conf file to append>] [-a|--all_tests] [-d|--mount_dir <dir1,dir2,...>] [-v|--verbose]
Run health checks on the current VM directly on the host.

  -h, --help               Display this help message.
  -c, --config             Optional path to a custom NHC config file. 
                           If not specified, the VM SKU will be detected and the appropriate conf file used.
  -o, --output             Optional path for health check log output (default: ./health.log).
  -e, --append_conf        Path to an additional conf file to append to the base config.
  -t, --timeout            Optional timeout (in seconds) for each health check (default: 500 seconds).
  -a, --all                Run ALL checks; do not exit on first failure.
  -d, --mount_dir          (Ignored in host mode) Originally for mounting additional directories.
  -v, --verbose            Enable verbose and debug output.

EOF
}

# Parse arguments using getopt
options=$(getopt -l "help,config:,output:,timeout:,append_conf:,all:,mount_dir:,verbose" -o "hc:o:t:e:d:v:a" -a -- "$@")
if [ $? -ne 0 ]; then
    print_help
    exit 1
fi

eval set -- "$options"
while true; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        -c|--config)
            shift
            CONF_FILE="$(realpath -e ${1//\~/$HOME})"
            ;;
        -o|--output)
            shift
            OUTPUT_PATH="$(realpath -m ${1//\~/$HOME})"
            ;;
        -e|--append_conf)
            shift
            APPEND_CONF_PATH="$(realpath -m ${1//\~/$HOME})"
            ;;
        -t|--timeout)
            shift
            TIMEOUT="$1"
            ;;
        -d|--mount_dir)
            shift
            USER_DIRS="$1"
            ;;
        -v|--verbose)
            VERBOSE=true
            ;;
        -a|--all)
            RUN_ALL=true
            ;;
        --)
            shift
            break
            ;;
    esac
    shift
done

# Function to collect meta data for the VM and host.
function collect_meta_data(){
    pHostName=$(python3 "${AZ_NHC_ROOT}/getPhysHostName.py")
    computerName=$(echo $pHostName | awk '{print $1}')
    physHostName=$(echo $pHostName | awk '{print $4}')
    vmhostname=$(hostname)
    vmid=$(curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-03-01&format=text")
    vm_name=$(curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/name?api-version=2021-11-15&format=text")
    kernelVersion=$(uname -r)
}

# Ensure the output log file exists
OUTPUT_PATH=$(realpath -m "$OUTPUT_PATH")
if [ ! -f "$OUTPUT_PATH" ]; then
    echo "Azure Healthcheck log" > "$OUTPUT_PATH"
fi

# Detect VM SKU and select the configuration file if not provided
SKU=$(curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text" | tr '[:upper:]' '[:lower:]' | sed 's/standard_//')
if [ -z "$CONF_FILE" ]; then
    echo "No custom config file specified, detecting VM SKU..."
    CONF_DIR="$AZ_NHC_ROOT/conf/"
    CONF_FILE="$CONF_DIR/$SKU.conf"
    echo "$CONF_DIR"
    echo "$CONF_FILE"

    if [ -e "$CONF_FILE" ]; then
        echo "Running health checks for Standard_${SKU} SKU..."
    else
        echo "The VM SKU 'standard_${SKU}' is not supported by Azure health checks." | tee -a "$OUTPUT_PATH"
        exit 0
    fi

    # If accelerated networking is detected, append the additional test (if not already in the config)
    acc_file="$CONF_FILE"
    acc_net=$(ibstatus mlx5_an0 2>/dev/null)
    if [ $? -eq 0 ] && ! grep -q 'mlx5_an0:1' "$acc_file"; then
        echo -e "\n\n### Accelerated network check\n * || check_hw_ib 40  mlx5_an0:1\n * || check_hw_eth eth1" >> "$acc_file"
    fi
fi

# Validate the config file exists
CONF_FILE=$(realpath -e "$CONF_FILE")
if [ ! -f "$CONF_FILE" ]; then
    echo "The config file $CONF_FILE does not exist. Please specify a valid config file."
    exit 1
fi

# If an additional conf file was specified, append it to the base configuration.
if [ -n "$APPEND_CONF_PATH" ]; then
    if [ ! -f "$APPEND_CONF_PATH" ]; then
        echo "Append conf file $APPEND_CONF_PATH does not exist."
        exit 1
    fi
    conf_dir=$(dirname "$CONF_FILE")
    default_name="$(basename "$CONF_FILE" .conf)"
    combined_conf="$conf_dir/${default_name}_appended.conf"
    cat "$CONF_FILE" > "$combined_conf"
    echo -e "\n\n#######################################################################\n### APPENDED Config File: $APPEND_CONF_PATH \n" >> "$combined_conf"
    cat "$APPEND_CONF_PATH" >> "$combined_conf"
    CONF_FILE="$combined_conf"
fi

# Prepare the arguments that will be passed to the health check runner.
nhc_args=()
if [ "$VERBOSE" = true ]; then
    nhc_args+=("-v")
    nhc_args+=("-d")
fi
if [ "$RUN_ALL" = true ]; then
    nhc_args+=("-a")
fi
NHC_ARGS=${nhc_args[@]}

# Determine the kernel log file (either syslog or messages)
if [ -f /var/log/syslog ]; then
    kernel_log="/var/log/syslog"
elif [ -f /var/log/messages ]; then
    kernel_log="/var/log/messages"
else
    echo "Neither syslog nor messages log was found in /var/log; proceeding without kernel log."
    kernel_log=""
fi

# Collect VM meta data
collect_meta_data

# Append meta data to the output log
cat <<EOF >> "$OUTPUT_PATH"
------ VM Meta Data ------
VM NAME: $vm_name
COMPUTER NAME: $computerName
VM HOST NAME: $vmhostname
VM ID: $vmid
VM SKU: standard_${SKU}
PHYSICAL HOST NAME: $physHostName
Kernel Version: $kernelVersion
EOF

# (Optional) Process additional directories if provided.
# In host mode, these directories should already be accessible; this section is retained for logging purposes.
if [ -n "$USER_DIRS" ]; then
    IFS=',' read -ra DIR_ARRAY <<< "$USER_DIRS"
    for host_dir in "${DIR_ARRAY[@]}"; do
        if [ -d "$host_dir" ]; then
            echo "Additional directory available: $host_dir"
        else
            echo "Directory $host_dir does not exist, skipping."
        fi
    done
fi

echo "Running health checks using config: $CONF_FILE"
echo "Health check log output: $OUTPUT_PATH"

# Detect GPU vendor (this variable can be used by the entrypoint script/tests)
if lspci | grep -iq NVIDIA ; then
    GPU_VENDOR="nvidia"
elif lspci | grep -iq AMD ; then
    GPU_VENDOR="amd"
else
    GPU_VENDOR="cpu"
fi

# Export environment variables for the entrypoint script to use.
export TIMEOUT
export NHC_ARGS
export AZ_NHC_CONF_FILE="$CONF_FILE"     # Path to the configuration file
export AZ_NHC_OUTPUT_FILE="$OUTPUT_PATH"   # Log file for output
export AZ_NHC_SYSLOG_FILE="$kernel_log"     # Kernel log location (if available)
export GPU_VENDOR

# Run the health check entrypoint script directly.
# (Ensure that aznhc-entrypoint.sh is executable and adapted to use the environment variables above.)
bash "$AZ_NHC_ROOT/aks/ubuntu2204/host_entrypoint.sh"
