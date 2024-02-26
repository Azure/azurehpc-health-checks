#!/bin/bash

AZ_NHC_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCK_IMG_NAME="aznhc.azurecr.io/nvrt"
DOCK_CONT_NAME=aznhc


function print_help() 
{
cat << EOF

Usage: ./run-health-checks.sh [-h|--help] [-c|--config <path to an NHC .conf file>] [-o|--output <directory path to output all log files>] [-a|--all_tests] [-d|--mount_dir] [-v|--verbose]
Run health checks on the current VM.

-h, -help,          --help                  Display this help
-c, -config,        --config                Optional path to a custom NHC config file. 
                                            If not specified the current VM SKU will be detected and the appropriate conf file will be used.

-o, -output,        --output                Optional path to output the health check logs to. All directories in the path must exist.
                                            If not specified it will use output to ./health.log

-t, -timeout,       --timeout               Optional timeout in seconds for each health check. If not specified it will default to 500 seconds.

-a, -all,     --all                         Run ALL checks; don't exit on first failure.

-d, -mount_dir,     --mount_dir             Optional path to mount directories to the docker container. Provide single directory or comma separate directories.
                                            All directories will have the same path but with the prefix /mnt/ added to the path within the container.

-v, -verbose,       --verbose               If set, enables verbose and debug outputs.


EOF
}

CONF_FILE=""
OUTPUT_PATH="./health.log"
TIMEOUT=500
VERBOSE=false

options=$(getopt -l "help,config:,output:,timeout:,all:,verbose" -o "hac:o:t:d:v" -a -- "$@")
if [ $? -ne 0 ]; then
    print_help
    exit 1
fi

eval set -- "$options"
while true
do
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
    break;;
esac
shift
done

OUTPUT_PATH=$(realpath -m "$OUTPUT_PATH")

# If a custom configuration isn't specified, detect the VM SKU and use the appropriate conf file
if [ -z "$CONF_FILE" ]; then
    echo "No custom conf file specified, detecting VM SKU..."
    SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text" | tr '[:upper:]' '[:lower:]' | sed 's/standard_//')
    CONF_DIR="$AZ_NHC_ROOT/conf/"
    CONF_FILE="$CONF_DIR/$SKU.conf"
    if [ -e "$CONF_FILE" ]; then
        echo "Running health checks for Standard_$SKU SKU..."
    else
        echo "The vm SKU 'standard_$SKU' is currently not supported by Azure health checks." | tee -a $OUTPUT_PATH
        exit 0
    fi

    AN40=("nd96asr_v4" "nd96amsr_a100_v4" "hb120rs_v3" "hb120-96rs_v3" "hb120-64rs_v3" "hb120-32rs_v3" "hb120-16rs_v3" "hb120rs_v2")
    AN100=("nc40ads_h100_v5" "nc80adis_h100_v5" "nd96isr_h100_v5" "hb176rs_v4" "hb176-144rs_v4" "hb176-96rs_v4"  "hb176-48rs_v4" "hb176-24rs_v4" "hx176rs" "hx176-144rs" "hx176-96rs" "hx176-48rs" "hx176-24rs" "nc96ads_a100_v4" "nc48ads_a100_v4" "nc24ads_a100_v4")

    if [[ " ${AN40[*]} " == *" $SKU "* ]]; then
        an_rate=40
    elif [[ " ${AN100[*]} " == *" $SKU "* ]]; then
        an_rate=100
    fi

    #add accelerated network if applicable, when using the default conf files, skip if an explicit conf file is specified
    acc_file=$CONF_FILE
    acc_net=$(ibstatus mlx5_an0 2>/dev/null)
    if [ $? -eq 0 ] && [ -n "$an_rate" ] && ! grep -q 'mlx5_an0:1' "$acc_file"; then
        echo -e "\n\n### Accelerate network check\n * || check_hw_ib $an_rate  mlx5_an0:1\n * || check_hw_eth eth1" >> $acc_file
    fi
fi

CONF_FILE=$(realpath -e "$CONF_FILE")
if [ ! -f "$CONF_FILE" ]; then
    echo "The conf file $CONF_FILE does not exist. Please specify a valid conf file."
    exit 1
fi


# Set NHC_ARGS
nhc_args=()
if [ "$VERBOSE" = true ]; then
    nhc_args+=("-v")
    nhc_args+=("-d")
fi
if [ "$RUN_ALL" = true ]; then
    nhc_args+=("-a")
fi
NHC_ARGS=${nhc_args[@]}

# get kernel log
if [ -f /var/log/syslog ]; then
    kernel_log=/var/log/syslog
elif [ -f /var/log/messages ]; then
    kernel_log=/var/log/messages
else
    echo "syslog or messages log was not found in /var/log proceeding without kernel log"
fi

# create log file if it doesn't exist
if [ ! -f $OUTPUT_PATH ]; then
    echo "Azure Healthcheck log" > $OUTPUT_PATH
fi

# mount additional directories
ADDITIONAL_MNTS=""
if [ -n "$USER_DIRS" ]; then
    for dir in $(echo $USER_DIRS | tr "," "\n"); do
        if [ -d "$dir" ]; then
            ADDITIONAL_MNTS+=" -v $dir:/mnt/$dir"
        else
            echo "Directory $dir does not exist, skipping"
        fi
    done
fi

echo "Running health checks using $CONF_FILE and outputting to $OUTPUT_PATH"

if lspci | grep -iq NVIDIA ; then
    NVIDIA_RT="--runtime=nvidia"
fi

WORKING_DIR="/azure-nhc"
DOCK_CONF_PATH="$WORKING_DIR/conf"
DOCKER_RUN_ARGS="--name=$DOCK_CONT_NAME --net=host  -e TIMEOUT=$TIMEOUT \
    --rm ${NVIDIA_RT} --cap-add SYS_ADMIN --cap-add=CAP_SYS_NICE --privileged \
    -v /sys:/hostsys/ \
    -v $CONF_FILE:"$DOCK_CONF_PATH/aznhc.conf" \
    -v $OUTPUT_PATH:$WORKING_DIR/output/aznhc.log \
    -v ${kernel_log}:$WORKING_DIR/syslog \
    -v ${AZ_NHC_ROOT}/customTests:$WORKING_DIR/customTests"

sudo docker run ${DOCKER_RUN_ARGS} -e NHC_ARGS="${NHC_ARGS}" "${DOCK_IMG_NAME}" bash -c "$WORKING_DIR/aznhc-entrypoint.sh"
