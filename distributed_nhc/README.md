# Distributed Node Health Check
Distributed NHC is an extension of Azure NHC which can easily dispatch, execute, and aggregate Azure NHC on an arbitrary collection of nodes.
The Node Health Check runs a variety of single node validation tests to validate the health of a given node.
These tests validate the presence and status of hardware on the node as well as a variety of GPU and IB performance tests to ensure expected bandwidths and throughputs are met.

## Setting up Distributed NHC
It is necessary to run Distributed NHC on a cluster in which all nodes have access to the same shared volume.
In all examples following, it is assumed that a shared volume named "/work" is mounted and accessible by all nodes. The name of the shared volume is not required to be /work

Provided this, you can simply clone the repository onto the /work volume and invoke ./distributed_nhc.sb.sh as described below.

## Running Distributed NHC
Distributed NHC is ran entirely with the distributed_nhc.sb.sh script.
This script supports two modes of execution, as a slurm sbatch or invoked directly which uses parallel-ssh.
Please note that NHC takes a few minutes (~5-8 minutes) to run and NHC itself produces very limited output until the results of the health check.
## Known Issues
Distributed NHC can fail when running on large sets of nodes (>300 nodes) as a single slurm job. 
The failure will manifest as an abnormally quick completion of NHC and every host failing the health check with the error “No results reported”
These failures have only been observed empirically on nodes sets of ~330 nodes while successfully being run on node sets of ~270 nodes.

A mitigation for this issue is to simply enqueue multiple distributed NHC jobs on smaller subsets of nodes.
For example, to test on a set of 330 nodes, running 3 jobs with 110 each is a suitable work around.
If you enqueue multiple distributed NHC jobs, do note that each job will produce it’s own .health.log report at the end. 

## Slurm
Running with slurm is the typical approach to running distributed NHC.
When doing so, all sbatch arguments to target specific sets of nodes are supported.
Running with slurm is the suggested approach when running on many nodes.

### Slurm Execution Examples
```
sbatch -w mynode-[001,003-007] ./distributed_nhc.sb.sh 
sbatch -F mynodelist.txt ./distributed_nhc.sb.sh 
sbatch -N35 --partition=p1 ./distributed_nhc.sb.sh
```

### Slurm Logs
All logs will end up in the logs directory at /work/distributed_nhc/logs provided the setup instructions have been followed.
There are three log files produced.
1.  distributed_nhc-{jobid}.out is the active standard output. You can tail -f this file to see activity.
2.  distributed_nhc-{jobid}.err is the active standard error.
3.  distributed_nhc-{jobid}-{timestamp}.health.log is the results of the health check. This file will only appear upon completion of the health check.
    See the Interpreting NHC Results section below for details on the health.log files.
4.  distributed_nhc-{jobid}-{timestamp}.debug.log is the very verbose debug logs. This file will only appear upon completion of the health check provided that -V/--verbose was set.
    See the Interpreting NHC Results section below.

## Parallel-SSH
Running with parallel-ssh by invoking distributed_nhc.sb.sh directly is the preferred approach to test drained nodes or nodes otherwise unreachable by slurm, as well as spot checking smaller sets of nodes.
When doing so, the node lists can be specified like sbatch using either -w or -F.
The script itself also supports the –help argument.

### Parallel-SSH Execution Examples
```
./distributed_nhc.sb.sh -w mynode-[001,003-007,12,018-023]
./distributed_nhc.sb.sh -F mynodelist.txt
```

### Parallel-SSH Logs
All logs will end up in the logs directory at ./distributed_nhc/logs provided the setup instructions have been followed.
There are three log files produced.
1.  distributed_nhc-pssh-{timestamp}.out is the active standard output. You can tail -f this file to see activity.
2.  distributed_nhc-pssh-{timestamp}.err is the active standard error.
3.  distributed_nhc-pssh-{timestamp}.health.log is the results of the health check. This file will only appear upon completion of the health check.
    See the Interpreting NHC Results section below.
4.  distributed_nhc-pssh-{timestamp}.debug.log is the very verbose debug logs. This file will only appear upon completion of the health check provided that -V/--verbose was set.
    See the Interpreting NHC Results section below.

## Customizing Test Set
You may want to rerun a specific test or subset of tests on problematic nodes rather than rerunning the entire health check.
To do so, make a copy of ../distributed_nhc/conf/nd96isr_h100_v5.conf
cp ./distributed_nhc/conf/nd96isr_h100_v5.conf ./distributed_nhc/mytests.conf
In this file you can comment out any test with # at the beginning of the line.
The execute the customized conf file you must specify it as an argument to distributed_nhc.sb.sh with the -c argument.
Modifying and saving the conf file ./distributed_nhc/conf/nd96isr_h100_v5.conf will not work unless you explicitly pass it as an argument with -c

For example:
```
sbatch -w mynode-[001,003-007] ./distributed_nhc.sb.sh -c ./mytests.conf
./distributed_nhc.sb.sh -w mynode-[001,003-007,12,018-023] -c ./mytests.conf
./distributed_nhc.sb.sh -w mynode-[001,003-007,12,018-023] -c ../conf/nd96isr_h100_v5.conf
```

Please note, if you modify the .conf file to run a limited set of tests, a node that reports Healthy only means it has passed that specific subset of tests.
The node could still be unhealthy and fail a test you have not run. Always verify a node is healthy by running the entire suite of tests (simply by not specifying -c)

## Interpreting NHC Results
The resulting health log file shows the health report for every node tested against.
The health logs appear in the ./distributed_nhc/logs directory with the extension .health.log
The debug logs appear in the ./distributed_nhc/logs directory with the extension .debug.log

### Health Results
The health results per node found in the .health.log files are always formatted as {hostname} | {health result}
 * A healthy node reports
   {hostname} | Healthy

 * A node that fails NHC reports
   {hostname} | ERROR: nhc: Health check failed: {details of the failure}

 * A node that failed for any reason other than NHC reports
   {hostname} | ERROR: No results reported

   The “No results reported” error is the catch-all for non-nhc errors meaning that no NHC results were reported by the node.
   This could mean a variety of things, but some common reasons may be:
    * The node is unreachable, check to see if you can ssh to the node.
    * The script onetouch_nhc.sh is unreachable by the node
        * Check to see if the shared volume /work is mounted.
        * Every node should have visibility into the /work/distributed_nhc directory.
    * Transient file handle errors, retry on that node.
    * Az NHC failed to download or install on the node.
        * Every node leaves a report of their own execution of NHC in the ~/onetouch_nhc/working directory.
        * Check the most recent .out and .err file to debug issues like this. 

#### Example Logs from Real Tests
Below is a sample of real outputs from .health.log files showing a variety of results.
```
mynode-042 | Healthy
mynode-066 | ERROR: nhc: Health check failed: check_gpu_xid: GPU Xid errors detected: [ 3606.832215] NVRM: Xid (PCI:0002:00:00): 119, pid=67769, name=nvidia-smi, Timeout waiting for RPC from GSP1! Expected function 76 (GSP_RM_CONTROL) (0x2080014b 0x5).
mynode-079 | ERROR: nhc: Health check failed: check_nccl_allreduce_ib_loopback: NCCL allreduce, BUS BW (expected >=40.0 GB/s, but measured 20.7377 GB/s)
mynode-084 | ERROR: nhc: Health check failed: Bandwidth is low on device 1. Reported bandwidth is 7 GB/s.
mynode-108 | ERROR: No results reported
mynode-123 | ERROR: nhc: Health check failed: Bandwidth is low on device 3. Reported bandwidth is 27 GB/s.
mynode-273 | ERROR: nhc: Health check failed: check_hw_ib: No IB port mlx5_ib7:1 is ACTIVE (LinkUp 400 Gb/sec).
mynode-510 | ERROR: nhc: Health check failed: check_gpu_ecc: GPU id 3: SRAM Uncorrectable ECC error count detected, (0,1)
```

### Debug Results
If ./distributed_nhc.sb.sh was ran with -V/--verbose then a .debug.log file will be produced.
This file contains dense, detailed logs of every NHC execution, including for nodes which report Healthy.
This can be useful as it also contains measured bandwidths and extra information about the NHC run.

#### Example Logs from Real Tests
Below is a sample of potentially useful information from a .debug.log file.
```
mynode-411 | Device 0 Device to Host reported bandwidth is 55 GB/s
mynode-411 | Device 0 Host to Device reported bandwidth is 55 GB/s
mynode-411 | Device 1 Device to Host reported bandwidth is 55 GB/s
mynode-411 | Device 1 Host to Device reported bandwidth is 55 GB/s
mynode-411 | Device 2 Device to Host reported bandwidth is 55 GB/s
mynode-411 | Device 2 Host to Device reported bandwidth is 55 GB/s
mynode-411 | Device 3 Device to Host reported bandwidth is 55 GB/s
mynode-411 | Device 3 Host to Device reported bandwidth is 55 GB/s
mynode-411 | Device 4 Device to Host reported bandwidth is 55 GB/s
mynode-411 | Device 4 Host to Device reported bandwidth is 55 GB/s
mynode-411 | Device 5 Device to Host reported bandwidth is 55 GB/s
mynode-411 | Device 5 Host to Device reported bandwidth is 55 GB/s
mynode-411 | Device 6 Device to Host reported bandwidth is 55 GB/s
mynode-411 | Device 6 Host to Device reported bandwidth is 55 GB/s
mynode-411 | Device 7 Device to Host reported bandwidth is 55 GB/s
mynode-411 | Device 7 Host to Device reported bandwidth is 55 GB/s
mynode-411 | IB devices=mlx5_ib0, mlx5_ib4: numa domains=0,1, Measured IB BW 390.98 Gbps
mynode-411 | IB devices=mlx5_ib1, mlx5_ib5: numa domains=0,1, Measured IB BW 390.98 Gbps
mynode-411 | IB devices=mlx5_ib2, mlx5_ib6: numa domains=0,1, Measured IB BW 390.99 Gbps
mynode-411 | IB devices=mlx5_ib3, mlx5_ib7: numa domains=0,1, Measured IB BW 390.98 Gbps
mynode-411 | Measured Avg NCCL allreduce bus BW 477.873 GB/s (expected >=460.0 GB/s)
mynode-411 | NCCL allreduce IB loopback bandwidth 46.3965 GB/s
```

## Kusto Export
There are two methods to export health and debug logs to Kusto.

### Manual Export
The script ./distributed_nhc/export_nhc_result_to_kusto.py can be used to manually export health and debug logs to Kusto.

It's requirements can be installed with
```
pip3 install -r ./distributed_nhc/requirements.txt
```

#### Example Usage
```
User Assigned Managed Identity
python3 ./export_nhc_result_to_kusto.py --ingest_url https://ingest-<cluster>.kusto.windows.net --database mydatabase --identity client_id -- my.health.log my.debug.log

System Assigned Managed Identity
python3 ./export_nhc_result_to_kusto.py --ingest_url https://ingest-<cluster>.kusto.windows.net --database mydatabase --identity -- my.health.log my.debug.log

Default Azure Credentials
python3 ./export_nhc_result_to_kusto.py --ingest_url https://ingest-<cluster>.kusto.windows.net --database mydatabase -- my.health.log my.debug.log

Specifying Custom Table Names
python3 ./export_nhc_result_to_kusto.py --ingest_url https://ingest-<cluster>.kusto.windows.net --database mydatabase --health_table_name MyHealthTable --debug_table_name MyDebugTable -- my.health.log my.debug.log
```

### Automated Export
./distributed_nhc.sb.sh supports similar arguments as ./export_nhc_result_to_kusto.py to automatically export health and debug logs to Kusto.

If an ingest_url is specified, the health and debug logs will be automatically exported to Kusto upon completion of the health check. Additionally the prerequisites for ./export_nhc_result_to_kusto.py will be installed.

#### Example Usage
```
User Assigned Managed Identity
./distributed_nhc.sb.sh -w mynode --kusto-export-url https://ingest-<cluster>.kusto.windows.net --kusto-database mydatabase --kusto-identity client_id

System Assigned Managed Identity
./distributed_nhc.sb.sh -w mynode --kusto-export-url https://ingest-<cluster>.kusto.windows.net --kusto-database mydatabase --kusto-identity

Default Azure Credentials
./distributed_nhc.sb.sh -w mynode --kusto-export-url https://ingest-<cluster>.kusto.windows.net --kusto-database mydatabase

Specifying Custom Table Names
./distributed_nhc.sb.sh -w mynode --kusto-export-url https://ingest-<cluster>.kusto.windows.net --kusto-database mydatabase --kusto-health-table MyHealthTable --kusto-debug-table MyDebugTabl
```

### Table Schema
The default table name and it's CSL Schema for the health and debug tables are as follows
```
NodeHealthCheck: Timestamp:datetime,JobName:string,Hostname:string,Healthy:bool,RawResult:string
NodeHealthCheck_Debug: Timestamp:datetime,JobName:string,Hostname:string,DebugLog:string
``` 