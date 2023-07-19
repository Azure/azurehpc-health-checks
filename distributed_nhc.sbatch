#!/bin/bash
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --job-name distributed_nhc
#SBATCH --error="logs/%x-%j.err"
#SBATCH --output="logs/%x-%j.out"
#SBATCH --time 00:15:00
srun ./onetouch_nhc.sh | grep "NHC-RESULT" | sed 's/NHC-RESULT //g' | sort