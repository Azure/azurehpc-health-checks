#!/bin/bash
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --job-name distributed_nhc
#SBATCH --error="logs/%x-%j.err"
#SBATCH --output="logs/%x-%j.out"
#SBATCH --time 00:15:00

# Running with SLURM
if [ -n "$SLURM_JOB_NAME" ] && [ "$SLURM_JOB_NAME" != "interactive" ]; then
    srun ./onetouch_nhc.sh | grep "NHC-RESULT" | sed 's/NHC-RESULT //g' | sort
    exit 0
fi

# Running with Parallel SSH
print_help() {
cat << EOF  
Usage: ./distributed_nhc.sb.sh [-h|--help] [--nodefile <path to nodefile>]
Run Azure NHC distributed onto the specified set of nodes and collects the results. Script can also be ran directly with sbatch. Running it as a shell script will use parallel-ssh

-h, -help,          --help                  Display this help

-F                  --nodefile              File contains a list of hostnames to connect to and run NHC on. Similar to slurm's sbatch -F/--nodefile argument
EOF
}

# Arguments
NODEFILE=""

# Parse out arguments
options=$(getopt -l "help,nodefile:" -o "hF:" -a -- "$@")
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
--)
    shift
    break;;
esac
shift
done

output_path="logs/distributed_nhc-pssh-$(date +"%Y-%m-%d_%H-%M-%S").out"

timeout=900 # 15 minute timeout
onetouch_nhc_path=$(realpath "./onetouch_nhc.sh")

output=$(parallel-ssh -P -t $timeout -h $NODEFILE $onetouch_nhc_path)
echo "$output" | grep "NHC-RESULT" | sed 's/NHC-RESULT //g' | sed "s/.*: //g" | sort > $output_path