#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name distributed_nhc
#SBATCH --error="logs/%x-%j.err"
#SBATCH --output="logs/%x-%j.out"
#SBATCH --time 00:30:00

print_help() {
cat << EOF  
Usage: ./distributed_nhc.sb.sh [-h|--help] [-F|--nodefile <path to nodefile>] [-w|--nodelist <slurm node list>]
Run Azure NHC distributed onto the specified set of nodes and collects the results. Script can also be ran directly with sbatch. Running it as a shell script will use parallel-ssh

Example Usage:
    sbatch -N4 ./distributed_nhc.sb.sh
    sbatch -N4 ./distributed_nhc.sb.sh -v <commit_sha>
    ./distributed_nhc.sb.sh -F ./my_node_file
    ./distributed_nhc.sb.sh -w node1,node2,node3
    ./distributed_nhc.sb.sh -F ./my_node_file -w additonal_node1,additional_node2

-h      --help                  Display this help

Node Selection - Applies to direct shell script usage only, pass these arguments to sbatch to run with SLURM

-F      --nodefile              File contains a list of hostnames to connect to and run NHC on. Similar to slurm's sbatch -F/--nodefile argument

-w      --nodelist              Comma seperate list of hostnames to connect to and run NHC on. Similar to slurm's sbatch -w/--nodelist argument but does not support ranges of hosts (eg host[1-5,7,...]).
                                            If -F/--nodefile is provided, any nodes specified with -w/--nodelist will be added to the list of hostnames to run NHC on. This does not modify the provided -F/--nodefile file.

NHC Behavior - Applies to both SLURM and direct shell script usage

-v      --version               Optional version of Az NHC to download from git, defaults to latest from "main"
                                            Can be a branch name like "main" for the latest or a full commit hash for a specific version.

-g      --git                   Optional git url to download az nhc from. Defaults to "https://github.com/Azure/azurehpc-health-checks"

-c      --config                Optional path to a custom NHC config file. 
                                            If not specified the current VM SKU will be detected and the appropriate conf file will be used.

-f      --force                 If set, forces the NHC script the redownload and reinstall everything

-V      --verbose               If set, enables verbose mode which will output all detailed debug file to stdout and a .debug.log file next to the .health.log file

Kusto Exporting - Applies to both SLURM and direct shell script usage

                    --kusto-export-url      Optional Kusto Ingest URL to export results to. If not specified, results will not be exported to Kusto          
                    --kusto-database        If kusto-export-url is specified, this is required and is the database to export results to. 

                    --kusto-identity        If kusto-export-url is specified, this is optional and is the identity to use to authenticate to Kusto.
                                            If not provided, will use DefaultAzureCredential to authenticate.
                                            If provided but with no client ID, will use System Assigned Identity to authenticate. For example by just specifying '--kusto-identity' with no value.
                                            If provided with a client ID, will use User Assigned Identity to authenticate. For example by specifying '--kusto-identity my_client_id'.

                    --kusto-health-table    If kusto-export-url is specified, this is optional and is the table to export health results to. Defaults to "NodeHealthCheck"
                    --kusto-debug-table     If kusto-export-url is specified, this is optional and is the table to export health results to. Defaults to "NodeHealthCheck_Debug"
EOF
}

expand_nodelist() {
    nodelist="$1"
    # make nodelist bash "friendly" for expansion
    # ie turn "aice-ndv5-iad21-[000170,000201-000203,000218-000220]"
    # into "aice-ndv5-iad21-{000170,{000201..000203},{000218..000220}}"
    # which bash can easily expand into
    # aice-ndv5-iad21-000170 aice-ndv5-iad21-000201 aice-ndv5-iad21-000202 aice-ndv5-iad21-000203 aice-ndv5-iad21-000218 aice-ndv5-iad21-000219 aice-ndv5-iad21-000220

    # converts "aice-ndv5-iad21-[000170,000201-000203,000218-000220]"
    # into "aice-ndv5-iad21- [000170,000201-000203,000218-000220]" 
    # which we can then stick into an array. If we have 1 element, there were no ranges 
    # otherwise, expand the ranges and rebuild the node names 
    host_num_split=( $( echo $nodelist | sed -r "s/(.*)(\[.*\]).*/\1 \2/" ) )
    if [ ${#host_num_split[@]} -eq 1 ]; then
        echo ${host_num_split[0]}
        return
    fi

    nodenumbers=${host_num_split[1]}
    bash_friendly_ranges=$(echo $nodenumbers | sed -r -e 's:[[](.*)[]]:{\1}:' -e 's:([0-9]+)[-]([0-9]+):{\1..\2}:g')
    bash_friendly_node_range="${host_num_split[0]}$bash_friendly_ranges"
    eval echo $bash_friendly_node_range | tr -d '{}'
}

# Shared Variables
RAW_OUTPUT=""
HEALTH_LOG_FILE_PATH=""
DEBUG_LOG_FILE_PATH=""
NODELIST_ARR=()
ONETOUCH_NHC_PATH=$(realpath -e "./onetouch_nhc.sh")
ONETOUCH_NHC_ARGS=()
VERBOSE="False"

KUSTO_EXPORT_ENABLED="False"
KUSTO_EXPORT_ARGS=()
KUSTO_IDENTITY="False" # hold onto this seperately to help with the passing arguments to the export script

nhc_start_time=$(date +%s.%N)


if [ -n "$SLURM_JOB_NAME" ] && [ "$SLURM_JOB_NAME" != "interactive" ]; then
    EXECUTION_MODE="SLURM"

    # Setup variables for SLURM
    NODELIST_ARR=( $(expand_nodelist $SLURM_JOB_NODELIST) )
    NHC_JOB_NAME="$SLURM_JOB_NAME-$SLURM_JOB_ID-$(date +'%Y-%m-%d_%H-%M-%S')"
    HEALTH_LOG_FILE_PATH=$(realpath -m "./logs/$NHC_JOB_NAME.health.log")
    DEBUG_LOG_FILE_PATH=$(realpath -m "./logs/$NHC_JOB_NAME.debug.log")

else
    EXECUTION_MODE="PSSH"

    # Setup variables for PSSH, Nodefile and Nodelist are handled in the argument parsing
    NHC_JOB_NAME="distributed_nhc-pssh-$(date --utc +'%Y-%m-%d_%H-%M-%S')"
    HEALTH_LOG_FILE_PATH=$(realpath -m "./logs/$NHC_JOB_NAME.health.log")
    DEBUG_LOG_FILE_PATH=$(realpath -m "./logs/$NHC_JOB_NAME.debug.log")
fi

echo "Running in $EXECUTION_MODE mode"

# These options are shared by both SLURM and PSSH
SHARED_SHORT_OPTS="hv:c:fg:V"
SHARED_LONG_OPTS="help,version:,git:,config:,force,verbose,kusto-export-url:,kusto-database:,kusto-identity::,kusto-health-table:,kusto-debug-table"

# These options are only needed by PSSH
PSSH_SHORT_OPTS="F:w:"
PSSH_LONG_OPTS="nodefile:,nodelist:"

# Select options based on execution mode
if [ "$EXECUTION_MODE" == "SLURM" ]; then
    # SLURM
    options=$(getopt -l "$SHARED_LONG_OPTS" -o "$SHARED_SHORT_OPTS" -- "$@")
else
    # PSSH
    options=$(getopt -l "$SHARED_LONG_OPTS,$PSSH_LONG_OPTS" -o "$SHARED_SHORT_OPTS,$PSSH_SHORT_OPTS" -- "$@")
fi

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
# PSSH Options
-F|--nodefile) 
    shift
    if [ "$EXECUTION_MODE" == "SLURM" ]; then
        echo "Cannot specify -F/--nodefile when running with SLURM, please pass node file to sbatch instead"
        exit 1
    fi

    if [ ! -f "$1" ]; then
        echo "Nodefile $1 does not exist"
        exit 1
    fi

    if [ -f "$1" ]; then
        mapfile -t NODELIST_ARR < $1
    fi
    ;;
-w|--nodelist) 
    shift
    if [ "$EXECUTION_MODE" == "SLURM" ]; then
        echo "Cannot specify -w/--nodelist when running with SLURM, please pass node list to sbatch instead"
        exit 1
    fi

    echo "Adding nodes from nodelist $1"
    NODELIST_ARR+=( $(expand_nodelist $1 ) )
    ;;
# Shared Onetouch NHC Args
-v|--version) 
    shift
    ONETOUCH_NHC_ARGS+=("-v" "$1")
    ;;
-g|--git) 
    shift
    ONETOUCH_NHC_ARGS+=("-g" "$1")
    ;;
-c|--config) 
    shift
    CUSTOM_CONF="$(realpath -e ${1//\~/$HOME})"
    ONETOUCH_NHC_ARGS+=("-c" "$CUSTOM_CONF")
    ;;
-f|--force)
    ONETOUCH_NHC_ARGS+=("-f")
    ;;
-V|--verbose)
    ONETOUCH_NHC_ARGS+=("-V")
    VERBOSE="True"
    ;;
# Shared Kusto Export Args
--kusto-export-url) 
    shift
    echo "Setting Kusto export url to $1"
    KUSTO_EXPORT_ENABLED="True"
    KUSTO_EXPORT_ARGS+=("--ingest_url" "$1")
    ;;
--kusto-database) 
    shift
    echo "Setting Kusto database to $1"
    KUSTO_EXPORT_ARGS+=("--database" "$1")
    ;;
--kusto-identity) 
    shift
    echo "Setting Kusto identity to $1"
    KUSTO_IDENTITY="$1"
    # Handle case of no client id provided
    if [ -z "$KUSTO_IDENTITY" ]; then
        echo "No client id provided, using system assigned identity"
        KUSTO_IDENTITY="True"
    fi
    ;;
--kusto-health-table) 
    shift
    echo "Setting Kusto health table to $1"
    KUSTO_EXPORT_ARGS+=("--health_table_name" "$1")
    ;;
--kusto-debug-table)
    shift
    echo "Setting Kusto debug table to $1"
    KUSTO_EXPORT_ARGS+=("--debug_table_name" "$1")
    ;;
--)
    shift
    break;;
esac
shift
done

echo "Running with the following arguments:"
echo "OneTouch NHC Args: ${ONETOUCH_NHC_ARGS[@]}"
echo 
echo "Node list: ${NODELIST_ARR[@]}"
echo 
echo "Kusto export enabled: $KUSTO_EXPORT_ENABLED"
echo "Kusto Args: ${KUSTO_EXPORT_ARGS[@]}"
echo "Kusto identity: $KUSTO_IDENTITY"
echo
echo "The rest of the arguments are: $@"
echo
echo "Early exit for testing"
echo

if [ ${#NODELIST_ARR[@]} -eq 0 ]; then
    echo "No nodes provided, must provide at least one node either from a file with -F/--nodefile or as a slurm node list with -w/--nodelist"
    echo
    print_help
    exit 1
fi

NODELIST_ARR=( $(echo "${NODELIST_ARR[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ') )

# Running with SLURM
if [ $EXECUTION_MODE == "SLURM" ]; then
    # verify file presence on all nodes
    { RAW_OUTPUT=$(srun --gpus-per-node=8 $ONETOUCH_NHC_PATH -n $NHC_JOB_NAME $@ | tee /dev/fd/3 ); } 3>&1
else
    # Running with Parallel SSH

    # Log file paths
    output_path="logs/$NHC_JOB_NAME.out"
    error_path="logs/$NHC_JOB_NAME.err"

    # Pssh args
    timeout=900 # 15 minute timeout
    
    pssh_host_args=()
    for node in "${NODELIST_ARR[@]}"; do
        pssh_host_args+="-H $node "
    done

    echo "Running Parallel SSH Distributed NHC on:" 
    echo "${NODELIST_ARR[@]}" | tr ' ' '\n' 
    echo "======================"
    echo "The health check is running, it will take a few minutes to complete."
    RAW_OUTPUT=$(parallel-ssh -P -t $timeout ${pssh_host_args[@]} $ONETOUCH_NHC_PATH ${ONETOUCH_NHC_ARGS[@]} 3> $error_path | tee $output_path)
fi

nhc_end_time=$(date +%s.%N)
nhc_duration=$(printf "%.2f" $(echo "($nhc_end_time - $nhc_start_time) / 60" | bc -l))

# Filter down to NHC-RESULTS
NHC_RESULTS=$(echo "$RAW_OUTPUT" | grep "NHC-RESULT" | sed 's/.*NHC-RESULT\s*//g')

if [ "$VERBOSE" == "True" ]; then
    # If Verbose was set, we expect NHC-DEBUG to be present 
    NHC_DEBUG=$(echo "$RAW_OUTPUT" | grep "NHC-DEBUG" | sed 's/.*NHC-DEBUG\s*//g')
    echo "Dumping NHC Debug into $DEBUG_LOG_FILE_PATH"
    echo "$NHC_DEBUG" | sort >> $DEBUG_LOG_FILE_PATH
fi

# Identify nodes who should have reported results but didn't, these failed for some unknown reason
nodes_with_results_arr=( $( echo "$NHC_RESULTS" | sed 's/\s*|.*//g' | tr '\n' ' ' ) )
nodes_missing_results=(`echo ${NODELIST_ARR[@]} ${nodes_with_results_arr[@]} | tr ' ' '\n' | sort | uniq -u`)

newline=$'\n'
for missing_node in "${nodes_missing_results[@]}"; do
    NHC_RESULTS+="$newline$missing_node | ERROR: No results reported"
done

echo "Health report can be found into $HEALTH_LOG_FILE_PATH"
echo "$NHC_RESULTS" | sort >> $HEALTH_LOG_FILE_PATH
echo "======================"
cat $HEALTH_LOG_FILE_PATH

echo "======================"
echo "NHC took $nhc_duration minutes to finish"
echo

# Export to Kusto if enabled
if [ "$KUSTO_EXPORT_ENABLED" == "True" ]; then
    # Place identity arg at the end (if specified)
    if [ "$KUSTO_IDENTITY" == "True" ]; then
        KUSTO_EXPORT_ARGS+=("--identity")
    elif [ -n "$KUSTO_IDENTITY" ]; then
        KUSTO_EXPORT_ARGS+=("--identity" "$KUSTO_IDENTITY")
    fi

    export_files=( "$HEALTH_LOG_FILE_PATH")
    if [ "$VERBOSE" == "True" ]; then
        export_files+=( "$DEBUG_LOG_FILE_PATH" )
    fi

    echo "Exporting results to Kusto"
    
    # Ensure prerequisites are installed
    requirements_file=$(realpath -e "./requirements.txt")
    pip install -r $requirements_file  > /dev/null 2>&1

    # Run export script
    kusto_export_script=$(realpath -e "./export_nhc_result_to_kusto.py")
    echo "Using export script $kusto_export_script"
    python3 $kusto_export_script ${KUSTO_EXPORT_ARGS[@]} $KUSTO_IDENTITY -- ${export_files[@]}
    echo "Ingestion queued, results take ~5 minutes to appear in Kusto"
fi