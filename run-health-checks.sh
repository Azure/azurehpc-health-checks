#!/bin/bash

source $(dirname "${BASH_SOURCE[0]}")/aznhc_env_init.sh

if [ "$EUID" -ne 0 ]; then
  echo "This script needs superuser privileges. Please run it with sudo."
  exit 1
fi

function install_check(){
    if ! command -v nhc &> /dev/null; then
        echo "NHC is not installed. Please install NHC before running health checks."
        exit 1
    fi
    # check if GPU custom test install is needed
    if lspci | grep -iq NVIDIA ; then
        if ! command -v $AZ_NHC_ROOT/bin/nvbandwidth &> /dev/null; then
            echo "NVBandwidth is not installed. Please rerun nhc install script."
            exit 1
        fi
    fi
    return 0
}

install_check

print_help() {
cat << EOF

Usage: ./run-health-checks.sh [-h|--help] [-c|--config <path to an NHC .conf file>] [-o|--output <directory path to output all log files>] [-e|--append_conf < path to conf file to be appended >] [-a|--all_tests] [-v|--verbose]
Run health checks on the current VM.

-h, -help,          --help                  Display this help

-c, -config,        --config                Optional path to a custom NHC config file. 
                                            If not specified the current VM SKU will be detected and the appropriate conf file will be used.

-o, -output,        --output                Optional path to output the health check logs to. All directories in the path must exist.
                                            If not specified it will use output to ./health.log

-t, -timeout,       --timeout               Optional timeout in seconds for each health check. If not specified it will default to 500 seconds.

-e, -append_conf,   --append_conf           Append a custom conf file to the conf file being used for the test. Useful if you have a set of common
                                            tests you want to add to the default conf files provided.

-a, -all,           --all                   Run ALL checks; don't exit on first failure.

-v, -verbose,       --verbose               If set, enables verbose and debug outputs.


EOF
}

CONF_FILE=""
OUTPUT_PATH="./health.log"
TIMEOUT=500
VERBOSE=false

options=$(getopt -l "help,config:,output:,extend_conf:,timeout:,all:,verbose" -o "hac:o:e:t:v" -a -- "$@")

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
-e|--append_conf)
    shift
    APPEND_CONF_PATH="$(realpath -m ${1//\~/$HOME})"
    ;;
-t|--timeout)
    shift
    TIMEOUT="$1"
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

nhc_args=()
if [ "$VERBOSE" = true ]; then
    nhc_args+=("-v")
    nhc_args+=("-d")
fi
if [ "$RUN_ALL" = true ]; then
    nhc_args+=("-a")
fi

#Appending

# Concatenate the test configuration file and with one passed in by the append argument.
# This will create a new config file with the postfix of appended.conf. The appended file path
# Will be printed in the new file
if [ ! -z $APPEND_CONF_PATH  ]; then
    if [ ! -f $APPEND_CONF_PATH ]; then
        echo "Append conf file $APPEND_CONF_PATH does not exist"
        exit 1
    fi
    conf_dir=$(dirname "$CONF_FILE")
    default_name="$(basename "$CONF_FILE" .conf)"
    combined_conf="$conf_dir/${default_name}_appended.conf"
    cat $CONF_FILE > $combined_conf
    echo -e "\n\n#######################################################################\n### APPENDED Conf File $APPEND_CONF_PATH \n" >> $combined_conf
    cat $APPEND_CONF_PATH >> $combined_conf
    CONF_FILE=$combined_conf
fi

echo "Running health checks using $CONF_FILE and outputting to $OUTPUT_PATH"

nhc ${nhc_args[@]} CONFFILE=$CONF_FILE LOGFILE=$OUTPUT_PATH TIMEOUT=$TIMEOUT 
