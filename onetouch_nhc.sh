#!/bin/bash
print_help() {
cat << EOF  
Usage: ./onetouch_nhc [-h|--help] [-v|--version <git version of Az NHC>] [-c|--config <path to an NHC .conf file>] [-w|--working <path to use as the working directory>] [-o|--output <path to output the health check logs>] [-f|--force]
Runs OneTouch Azure NHC which downloads a specific version of Azure NHC, installs pre-requisites, and executes a health check.

-h, -help,          --help                  Display this help

-v, -version,       --version               Optional version of Az NHC to download from git, defaults to latest from "main"
                                            Can be a branch name like "main" for the latest or a full commit hash for a specific version.

-c, -config,        --config                Optional path to a custom NHC config file. 
                                            If not specified the current VM SKU will be detected and the appropriate conf file will be used.

-w, -working,        --working              Optional path to specify as the working directory. This is where all content will be downloaded and executed from.
                                            If not specified it will default to the path "~/onetouch_nhc/"

-o, -output,        --output                Optional path to output the health check logs to. 
                                            If not specified will be output to a file under the working directory with a name following the format "\$(hostname)-\$(date +"%Y-%m-%d_%H-%M-%S")-health.log".

-f, -force,         --force                 If set, forces the script the redownload and reinstall everything

-e, -errors,         --errors               If set, forces the script to only print out errors 

-V, -verbose,        --verbose               If set, forces the script to only print out errors 
EOF
}

# Logging
LOG_VERBOSE=0
LOG_INFO=1
LOG_ERROR=2

# Arguments
VERSION="main"
WORKING_DIR=$(realpath -m "$HOME/onetouch_nhc/working")
CUSTOM_CONF=""
FORCE=false
LOG_LEVEL=$LOG_INFO

# Parse out arguments
options=$(getopt -l "help,version:,config:,working:" -o "hv:c:w:" -a -- "$@")
eval set -- "$options"
while true
do
case "$1" in
-h|--help) 
    print_help
    exit 0
    ;;
-v|--version) 
    shift
    VERSION="$1"
    ;;
-c|--config)
    shift
    CUSTOM_CONF="$(realpath -e ${1//\~/$HOME})"
    ;;
-w|--working)
    shift
    WORKING_DIR="$(realpath -m ${1//\~/$HOME})"
    ;;
-f|--force)
    FORCE=true
    ;;
-e|--errors)
    ERRORS_ONLY=$LOG_ERROR
    ;;
-V|--verbose)
    ERRORS_ONLY=$LOG_VERBOSE
    ;;
--)
    shift
    break;;
esac
shift
done

# Define expected paths
AZ_NHC_DIR=$(realpath -m "$WORKING_DIR/az-nhc-$VERSION")
INSTALL_SCRIPT_PATH="$AZ_NHC_DIR/install-nhc.sh"
RUN_HEALTH_CHECKS_SCRIPT_PATH="$AZ_NHC_DIR/run-health-checks.sh"
HEALTH_LOG_FILE_PATH="$AZ_NHC_DIR/$(hostname)-$(date +"%Y-%m-%d_%H-%M-%S")-health.log"

log() {
    host=$(hostname)
    ts=$(date +"%Y-%m-%d %H:%M:%S")
    level=$1
    
    if [ -z $level ]; then
        echo "A log level must be defined"
        exit 1
    fi

    msg="$2"

    if [ $level -ge $LOG_LEVEL ]; then
        echo "[$ts][$host] $msg"
    fi
}

log_verbose() { 
    if [ $# == 0 ]; then
        log $LOG_VERBOSE < /dev/stdin
    else
        log $LOG_VERBOSE "$1"
    fi
}
log_info() { 
    if [ $# == 0 ]; then
        log $LOG_INFO < /dev/stdin
    else
        log $LOG_INFO "$1"
    fi
}
log_error() { 
    if [ $# == 0 ]; then
        log $LOG_ERROR < /dev/stdin
    else
        log $LOG_ERROR "$1"
    fi
}

install_nhc() {
    force="$1"

    # attempt to see if NHC is installed with all custom tests
    NHC_INSTALLED=$(! $force)
    if $NHC_INSTALLED && [ -z $(which nhc) ]; then
        log_info "nhc is missing, reinstalling"
        NHC_INSTALLED=false
    fi
    
    if $NHC_INSTALLED && [[ $( diff --brief ./customTests /etc/nhc/scripts --exclude=lbnl_*.nhc --exclude=common.nhc | grep ".nhc" ) ]]; then
        log_info "Custom tests differ, reinstalling"
        NHC_INSTALLED=false
    fi

    if $NHC_INSTALLED; then
        log_info "NHC is installed with all custom tests"
    else
        log_info "Installing NHC"
        log_verbose < sudo $INSTALL_SCRIPT_PATH
    fi
}

setup_nhc() {
    version="$1"
    output_dir="$2"

    if [ -z $version ]; then
        log_error "A version must be provided"
        exit 1
    fi
    
    if [ -z $output_dir ]; then
        log_info "An output directory must be provided"
        exit 1
    fi

    if [ $FORCE ] && [ -d $output_dir ]; then
        if [ -f "$output_dir/install-nhc.sh" ] && [ -f "$output_dir/run-health-checks.sh" ]; then
            log_info "Version $version of AZ NHC is already downloaded at $output_dir"
            pushd $output_dir > /dev/null
            install_nhc $FORCE
            return 0
        fi
    fi

    archive_url="https://github.com/Azure/azurehpc-health-checks/archive/$version.tar.gz"
    log_verbose $(mkdir -p $output_dir)
    log_verbose $(wget -O - $archive_url | tar -xz --strip=1 -C $output_dir)

    # If we had to download, force re-install
    pushd $output_dir > /dev/null
    install_nhc true
}


run_health_checks() {
    log_file_path="$1"
    custom_conf="$2"

    if [ -z $log_file_path ]; then
        log_error "A log file path must be provided"
        exit 1
    fi

    log_file_path=$(realpath -m "$log_file_path")

    if [ -z $custom_conf ]; then
        # if no custom config is provided, let run-health-checks.sh auto-detect
        log_info $(sudo $RUN_HEALTH_CHECKS_SCRIPT_PATH $log_file_path)
    else
        # otherwise, run it ourselves
        custom_conf=$(realpath "$custom_conf")
        log_info "Running health checks using $custom_conf"
        log_info $(sudo nhc CONFFILE=$custom_conf LOGFILE=$log_file_path TIMEOUT=500)
    fi

}

# Download AZ NHC
log_info "Test info"

setup_nhc $VERSION $AZ_NHC_DIR 1
log_info "=== Finished Setting up AZ NHC ==="

# Execute Health Checks
run_health_checks $HEALTH_LOG_FILE_PATH $CUSTOM_CONF
log_info "=== Finished Running Health Checks ===" 
results=$(cat $HEALTH_LOG_FILE_PATH)

log_info "=== Overall Results ($HEALTH_LOG_FILE_PATH) ==="
log_info "$results"

echo
echo "=== Detected Errors (if any) ==="
if grep "ERROR" $HEALTH_LOG_FILE_PATH; then
    log_error $(grep "ERROR" $HEALTH_LOG_FILE_PATH)
    log_error "Errors found!"
    exit 1
else
    log_error "No errors found!"
    exit 0
fi