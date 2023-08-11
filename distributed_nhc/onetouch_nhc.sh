#!/bin/bash

print_help() {
cat << EOF  
Usage: ./onetouch_nhc [-h|--help] [-v|--version <git version of Az NHC>] [-c|--config <path to an NHC .conf file>] [-w|--working <path to use as the working directory>] [-o|--output <directory path to output all log files>] [-n|--name <name of the NHC job being ran>] [-f|--force]
Runs OneTouch Azure NHC which downloads a specific version of Azure NHC, installs pre-requisites, and executes a health check.

-h, -help,          --help                  Display this help

-v, -version,       --version               Optional version of Az NHC to download from git, defaults to latest from "main"
                                            Can be a branch name like "main" for the latest or a full commit hash for a specific version.

-g, -git,           --git                   Optional git url to download Az NHC from. Defaults to "https://github.com/Azure/azurehpc-health-checks"

-c, -config,        --config                Optional path to a custom NHC config file. 
                                            If not specified the current VM SKU will be detected and the appropriate conf file will be used.

-w, -working,        --working              Optional path to specify as the working directory. This is where all content will be downloaded and executed from.
                                            If not specified it will default to the path "~/onetouch_nhc/"

-o, -output,        --output                Optional directory path to output the health check, stdout, and stderr logs to. 
                                            If not specified it will use the same as the working directory".

-n, -name,          --name                  Optional name to provide for a given execution run. This impacts the names of the log files generated.
                                            If not specified the job name will be generated with "\$(hostname)-\$(date +"%Y-%m-%d_%H-%M-%S")".

-f, -force,         --force                 If set, forces the script the redownload and reinstall everything
EOF
}

# Arguments
VERSION="main"
GIT_URL="https://github.com/mpwillia/azurehpc-health-checks"
WORKING_DIR=$(realpath -m "$HOME/onetouch_nhc/working")
OUTPUT_DIR=$WORKING_DIR
JOB_NAME="$(hostname)-$(date --utc +"%Y-%m-%d_%H-%M-%S")"
CUSTOM_CONF=""
FORCE=false

# Parse out arguments
options=$(getopt -l "help,version:,config:,working:,output:,name:,force,git:" -o "hv:c:w:o:n:fg:" -a -- "$@")

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
-v|--version) 
    shift
    VERSION="$1"
    ;;
-g|--git) 
    shift
    GIT_URL="$1"
    ;;
-c|--config)
    shift
    CUSTOM_CONF="$(realpath -e ${1//\~/$HOME})"
    ;;
-w|--working)
    shift
    WORKING_DIR="$(realpath -m ${1//\~/$HOME})"
    ;;
-o|--output)
    shift
    OUTPUT_DIR="$(realpath -m ${1//\~/$HOME})"
    ;;
-n|--name)
    shift
    JOB_NAME="$1"
    ;;
-f|--force)
    FORCE=true
    ;;
--)
    shift
    break;;
esac
shift
done

# extract git info from url
git_url_parts=($(echo "$GIT_URL" | tr '/' ' '))
user_repo=$(echo "${git_url_parts[@]: -2:2}" | tr ' ' '_')

# Define expected paths
AZ_NHC_DIR=$(realpath -m "$WORKING_DIR/$user_repo-$VERSION")
INSTALL_SCRIPT_PATH="$AZ_NHC_DIR/install-nhc.sh"
RUN_HEALTH_CHECKS_SCRIPT_PATH="$AZ_NHC_DIR/run-health-checks.sh"

OUT_LOG_FILE_PATH="$OUTPUT_DIR/$JOB_NAME.out"
ERR_LOG_FILE_PATH="$OUTPUT_DIR/$JOB_NAME.err"
HEALTH_LOG_FILE_PATH="$OUTPUT_DIR/$JOB_NAME.health.log"

# Setup redirection for the rest of the script
mkdir -p $OUTPUT_DIR
exec > >(tee $OUT_LOG_FILE_PATH) 2> >(tee $ERR_LOG_FILE_PATH >&2)

install_nhc() {
    force=$1

    # attempt to see if NHC is installed with all custom tests
    NHC_INSTALLED=true
    if $force; then
        NHC_INSTALLED=false
    fi

    if $NHC_INSTALLED && [ -z $(which nhc) ]; then
        echo "nhc is missing, reinstalling"
        NHC_INSTALLED=false
    fi
    
    if $NHC_INSTALLED && [[ $( diff --brief ../customTests /etc/nhc/scripts --exclude=lbnl_*.nhc --exclude=common.nhc | grep ".nhc" ) ]]; then
        echo "Custom tests differ, reinstalling"
        NHC_INSTALLED=false
    fi

    if $NHC_INSTALLED; then
        echo "NHC is installed with all custom tests"
    else
        echo "Installing NHC"
        sudo $INSTALL_SCRIPT_PATH
    fi
}

setup_nhc() {
    version="$1"
    output_dir="$2"

    if [ -z $version ]; then
        echo "A version must be provided"
        exit 1
    fi
    
    if [ -z $output_dir ]; then
        echo "An output directory must be provided"
        exit 1
    fi
    
    if ! $FORCE && [ -d $output_dir ]; then
        if [ -f "$output_dir/install-nhc.sh" ] && [ -f "$output_dir/run-health-checks.sh" ]; then
            echo "Version $version of AZ NHC is already downloaded at $output_dir"
            pushd $output_dir > /dev/null
            install_nhc $FORCE
            return 0
        fi
    fi

    archive_url="$GIT_URL/archive/$version.tar.gz"
    
    mkdir -p $output_dir > /dev/null
    wget -q -O - $archive_url | tar -xz --strip=1 -C $output_dir

    if [ $? -ne 0 ]; then
        echo "Failed to download and unpack archive from $archive_url"
        exit 1
    fi

    # If we had to download, force re-install
    pushd $output_dir > /dev/null
    install_nhc true
}


run_health_checks() {
    log_file_path="$1"
    custom_conf="$2"

    if [ -z $log_file_path ]; then
        echo "A log file path must be provided"
        exit 1
    fi

    log_file_path=$(realpath -m "$log_file_path")

    if [ -z $custom_conf ]; then
        # if no custom config is provided, let run-health-checks.sh auto-detect
        echo "The health check has been started, it will typically take a few minutes to complete"
        sudo $RUN_HEALTH_CHECKS_SCRIPT_PATH $log_file_path
    else
        # otherwise, run it ourselves
        custom_conf=$(realpath "$custom_conf")
        echo "Running health checks using $custom_conf"
        echo "The health check has been started, it will typically take a few minutes to complete"
        sudo nhc -d -v CONFFILE=$custom_conf LOGFILE=$log_file_path TIMEOUT=500
    fi

}

# Download AZ NHC
echo "Running OneTouch NHC with Job Name $JOB_NAME on host $(hostname)"
setup_nhc $VERSION $AZ_NHC_DIR 1
echo "=== Finished Setting up AZ NHC ==="

# Execute Health Checks
echo
run_health_checks $HEALTH_LOG_FILE_PATH $CUSTOM_CONF
echo "=== Finished Running Health Checks ===" 

echo
echo "=== Debug Dump ==="
debug=$(grep " DEBUG:" $HEALTH_LOG_FILE_PATH)
echo "$debug" | while read line 
do
    cleaned_line=$(echo "$line" | sed 's/^\[[0-9]*\] - DEBUG:  //')
    echo "NHC-DEBUG $(hostname) | $cleaned_line";
done

echo
echo "=== Overall Results ($HEALTH_LOG_FILE_PATH) ==="
cat $HEALTH_LOG_FILE_PATH

echo
echo "=== Detected Errors (if any) ==="
errors=$(grep "ERROR" $HEALTH_LOG_FILE_PATH)

if [ -n "$errors" ]; then
    echo "$errors" | while read line 
    do
        cleaned_line=$(echo "$line" | sed 's/^\[[0-9]*\] - //')
        echo "NHC-RESULT $(hostname) | $cleaned_line";
    done
else
    echo "NHC-RESULT $(hostname) | Healthy"
fi