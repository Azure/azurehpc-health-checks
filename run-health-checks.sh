#!/bin/bash

print_help() {
cat << EOF

Usage: ./run-health-checks.sh [-h|--help] [-c|--config <path to an NHC .conf file>] [-o|--output <directory path to output all log files>] [-v|--verbose]
Run health checks on the current VM.

-h, -help,          --help                  Display this help
-c, -config,        --config                Optional path to a custom NHC config file. 
                                            If not specified the current VM SKU will be detected and the appropriate conf file will be used.

-o, -output,        --output                Optional path to output the health check logs to. All directories in the path must exist.
                                            If not specified it will use output to ./health.log

-t, -timeout,       --timeout               Optional timeout in seconds for each health check. If not specified it will default to 500 seconds.

-v, -verbose,       --verbose               If set, enables verbose and debug outputs.

EOF
}

CONF_FILE=""
OUTPUT_PATH="./health.log"
TIMEOUT=500
VERBOSE=false

options=$(getopt -l "help,config:,output:,timeout:,verbose" -o "hc:o:t:v" -a -- "$@")

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
-v|--verbose)
    VERBOSE=true
    ;;
--)
    shift
    break;;
esac
shift
done

OUTPUT_PATH=$(realpath -m "$OUTPUT_PATH")

# If a custom configuration isn't specified, detect the VM SKU and use the appropriate conf file
if [ -z "$CUSTOM_CONF" ]; then
    echo "No custom conf file specified, detecting VM SKU..."

    SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")
    echo "Running health checks for $SKU SKU..."

    SKU="${SKU,,}"
    if echo "$SKU" | grep -q "nd96asr_v4"; then
        conf_name="nd96asr_v4"
    elif echo "$SKU" | grep -q "nd96amsr_a100_v4"; then
        conf_name="nd96amsr_a100_v4"
    elif echo "$SKU" | grep -q "nd96isr_h100_v5"; then
        conf_name="nd96isr_h100_v5"
    elif echo "$SKU" | grep -q "hb120rs_v2"; then
        conf_name="hb120rs_v2"
    elif echo "$SKU" | grep -q "hb120rs_v3"; then
        conf_name="hb120rs_v3"
    elif echo "$SKU" | grep -q "hb176rs_v4"; then
        conf_name="hb176rs_v4"
    elif  echo "$SKU" | grep -q "hb176-144rs_v4"; then
        conf_name="hb176-144rs_v4"
    elif  echo "$SKU" | grep -q "hb176-96rs_v4"; then
        conf_name="hb176-96rs_v4"
    elif  echo "$SKU" | grep -q "hb176-48rs_v4"; then
        conf_name="hb176-48rs_v4"
    elif  echo "$SKU" | grep -q "hb176-24rs_v4"; then
        conf_name="hb176-24rs_v4"
    elif echo "$SKU" | grep -q "hx176rs"; then
        conf_name="hx176rs"
    elif  echo "$SKU" | grep -q "hx176-144rs"; then
        conf_name="hx176-144rs"
    elif  echo "$SKU" | grep -q "hx176-96rs"; then
        conf_name="hx176-96rs"
    elif  echo "$SKU" | grep -q "hx176-48rs"; then
        conf_name="hx176-48rs"
    elif  echo "$SKU" | grep -q "hx176-24rs"; then
        conf_name="hx176-24rs"
    else
        echo "The vm SKU '$SKU' is currently not supported by Azure health checks." | tee -a $OUTPUT_PATH
        exit 0
    fi

    CONF_FILE="$(dirname "${BASH_SOURCE[0]}")/conf/$conf_name.conf"
fi

CONF_FILE=$(realpath -e "$CONF_FILE")

nhc_args=()
if [ "$VERBOSE" = true ]; then
    nhc_args+=("-v")
    nhc_args+=("-d")
fi

echo "Running health checks using $CONF_FILE and outputting to $OUTPUT_PATH"
nhc ${nhc_args[@]} CONFFILE=$CONF_FILE LOGFILE=$OUTPUT_PATH TIMEOUT=$TIMEOUT
