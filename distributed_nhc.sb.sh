#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name distributed_nhc
#SBATCH --error="logs/%x-%j.err"
#SBATCH --output="logs/%x-%j.out"
#SBATCH --time 00:30:00

print_help() {
cat << EOF  
Usage: ./distributed_nhc.sb.sh [-h|--help] [-F|--nodefile <path to nodefile>] [-F|--nodefile <path to nodefile>]
Run Azure NHC distributed onto the specified set of nodes and collects the results. Script can also be ran directly with sbatch. Running it as a shell script will use parallel-ssh

Example Usage:
    sbatch -N4 ./distributed_nhc.sb.sh
    sbatch -N4 ./distributed_nhc.sb.sh -v <commit_sha>
    ./distributed_nhc.sb.sh -F ./my_node_file
    ./distributed_nhc.sb.sh -w node1,node2,node3
    ./distributed_nhc.sb.sh -F ./my_node_file -w additonal_node1,additional_node2

-h, -help,          --help                  Display this help

-F                  --nodefile              File contains a list of hostnames to connect to and run NHC on. Similar to slurm's sbatch -F/--nodefile argument

-w                  --nodelist              Comma seperate list of hostnames to connect to and run NHC on. Similar to slurm's sbatch -w/--nodelist argument but does not support ranges of hosts (eg host[1-5,7,...]).
                                            If -F/--nodefile is provided, any nodes specified with -w/--nodelist will be added to the list of hostnames to run NHC on. This does not modify the provided -F/--nodefile file.

-v, -version,       --version               Optional version of Az NHC to download from git, defaults to latest from "main"
                                            Can be a branch name like "main" for the latest or a full commit hash for a specific version.

-g, -git,           --git                   Optional git url to download az nhc from. Defaults to "https://github.com/Azure/azurehpc-health-checks"

-c, -config,        --config                Optional path to a custom NHC config file. 
                                            If not specified the current VM SKU will be detected and the appropriate conf file will be used.

-f, -force,         --force                 If set, forces the NHC script the redownload and reinstall everything
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

RAW_OUTPUT=""
HEALTH_LOG_FILE_PATH=""
NODELIST_ARR=()
onetouch_nhc_path=$(realpath -e "./onetouch_nhc.sh")

# Running with SLURM
if [ -n "$SLURM_JOB_NAME" ] && [ "$SLURM_JOB_NAME" != "interactive" ]; then
    NHC_JOB_NAME="$SLURM_JOB_NAME-$SLURM_JOB_ID-$(date +'%Y-%m-%d_%H-%M-%S')"
    HEALTH_LOG_FILE_PATH="logs/$NHC_JOB_NAME.health.log"
    NODELIST_ARR=( $(expand_nodelist $SLURM_JOB_NODELIST) )

    # verify file presence on all nodes
    { RAW_OUTPUT=$(srun --gpus-per-node=8 $onetouch_nhc_path -n $NHC_JOB_NAME $@ | tee /dev/fd/3 ); } 3>&1
else
    # Running with Parallel SSH
    # Arguments
    NODEFILE=""
    NODELIST=""
    GIT_VERSION=""
    GIT_URL=""
    CUSTOM_CONF=""
    FORCE=false

    # Parse out arguments
    options=$(getopt -l "help,nodefile:,nodelist:,version:,config:,force,git" -o "hF:w:v:c:fg:" -a -- "$@")
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
    -F|--nodefile) 
        shift
        NODEFILE="$1"
        ;;
    -w|--nodelist) 
        shift
        NODELIST="$1"
        ;;
    -v|--version) 
        shift
        GIT_VERSION="$1"
        ;;
    -g|--git) 
        shift
        GIT_URL="$1"
        ;;
    -c|--config) 
        shift
        CUSTOM_CONF="$(realpath -e ${1//\~/$HOME})"
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

    # Parse out nodes
    NODELIST_ARR=()

    if [ -f "$NODEFILE" ]; then
        mapfile -t NODELIST_ARR < $NODEFILE
    fi

    if [ -n "$NODELIST" ]; then
        NODELIST_ARR+=( $(echo $NODELIST | sed "s/,/ /g") ) 
    fi

    if [ ${#NODELIST_ARR[@]} -eq 0 ]; then
        echo "No nodes provided, must provide at least one node either from a file with -F/--nodefile or as a comma seperate list with -w/--nodelist"
        echo
        print_help
        exit 1
    fi

    # Make unique and sorted
    NODELIST_ARR=( $(echo "${NODELIST_ARR[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ') )

    # Log file paths
    jobname="distributed_nhc-pssh-$(date +'%Y-%m-%d_%H-%M-%S')"
    HEALTH_LOG_FILE_PATH="logs/$jobname.health.log"
    output_path="logs/$jobname.out"
    error_path="logs/$jobname.err"

    # Pssh args
    timeout=900 # 15 minute timeout
    
    pssh_host_args=()
    for node in "${NODELIST_ARR[@]}"; do
        pssh_host_args+="-H $node "
    done

    nhc_args=()
    if [ -n "$GIT_VERSION" ]; then
        nhc_args+=("-v" "$GIT_VERSION")
    fi
    
    if [ -n "$GIT_URL" ]; then
        nhc_args+=("-g" "$GIT_URL")
    fi
    
    if [ -n "$CUSTOM_CONF" ]; then
        nhc_args+=("-c" "$CUSTOM_CONF")
    fi

    if $FORCE ; then
        nhc_args+=("-f")
    fi

    echo "Running Parallel SSH Distributed NHC on:" 
    echo "${NODELIST_ARR[@]}" | tr ' ' '\n' 
    echo "======================"
    RAW_OUTPUT=$(parallel-ssh -P -t $timeout ${pssh_host_args[@]} $onetouch_nhc_path ${nhc_args[@]} 3> $error_path | tee $output_path)
fi

# Filter down to NHC-RESULTS
NHC_RESULTS=$(echo "$RAW_OUTPUT" | grep "NHC-RESULT" | sed 's/.*NHC-RESULT\s*//g')

# Identify nodes who should have reported results but didn't, these failed for some unknown reason
nodes_with_results_arr=( $( echo "$NHC_RESULTS" | sed 's/\s*|.*//g' | tr '\n' ' ' ) )
nodes_missing_results=(`echo ${NODELIST_ARR[@]} ${nodes_with_results_arr[@]} | tr ' ' '\n' | sort | uniq -u`)

newline=$'\n'
for missing_node in "${nodes_missing_results[@]}"; do
    NHC_RESULTS+="$newline$missing_node | ERROR: No results reported"
done

echo "$NHC_RESULTS" | sort >> $HEALTH_LOG_FILE_PATH
cat $HEALTH_LOG_FILE_PATH