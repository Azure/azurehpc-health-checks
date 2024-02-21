#!/usr/bin/python3
import sys
import os
import json
from datetime import datetime
from csv import DictReader
from argparse import ArgumentParser
from azure.identity import ManagedIdentityCredential, DefaultAzureCredential
from azure.kusto.data import KustoConnectionStringBuilder
from azure.kusto.ingest import QueuedIngestClient, IngestionProperties
import pandas as pd

def ingest_health_log(health_file, creds, ingest_url, database, health_table_name):
    filename_parts = os.path.basename(health_file).split("-", maxsplit=2)
    ts_str = filename_parts[2].split(".")[0]
    ts = datetime.strptime(ts_str, "%Y-%m-%d_%H-%M-%S")

    job_name = filename_parts[1]

    if job_name == "pssh":
        job_name = f"{job_name}-{ts_str}"

    with open(health_file, 'r') as f:
        lines = f.readlines()
        reader = DictReader(lines, fieldnames = ["Hostname", "RawResult"], delimiter='|', restkey="extra")

        df = pd.DataFrame(reader)
        df['Timestamp'] = ts
        df['JobName'] = job_name
        df['NodeName'] = df.apply(lambda x: x['Hostname'].strip(), axis=1)
        df['RawResult'] = df.apply(lambda x: x['RawResult'].strip(), axis=1)
        df['Healthy'] = df.apply(lambda x: x['RawResult'] == "Healthy", axis=1)
        df = df[['Timestamp', 'JobName', 'Hostname', 'Healthy', 'RawResult']]

        ingest_client = QueuedIngestClient(KustoConnectionStringBuilder.with_azure_token_credential(ingest_url, creds))
        print(f"Ingesting health results from {os.path.basename(health_file)} into {ingest_url} at {database}/{health_table_name}")
        ingest_client.ingest_from_dataframe(df, IngestionProperties(database, health_table_name))

def ingest_debug_log(debug_file, creds, ingest_url, database, debug_table_name):
    filename_parts = os.path.basename(debug_file).split("-", maxsplit=2)
    ts_str = filename_parts[2].split(".")[0]
    ts = datetime.strptime(ts_str, "%Y-%m-%d_%H-%M-%S")

    job_name = filename_parts[1]

    if job_name == "pssh":
        job_name = f"{job_name}-{ts_str}"

    with open(health_file, 'r') as f: # should this be debug file?
        lines = f.readlines()
        reader = DictReader(lines, fieldnames = ["Hostname", "DebugLog"], delimiter='|', restkey="extra")

        df = pd.DataFrame(reader)
        df['Timestamp'] = ts
        df['JobName'] = job_name
        df['NodeName'] = df.apply(lambda x: x['Hostname'].strip(), axis=1)
        df['DebugLog'] = df.apply(lambda x: x['DebugLog'].strip(), axis=1)
        df = df[['Timestamp', 'JobName', 'Hostname', 'DebugLog']]

        ingest_client = QueuedIngestClient(KustoConnectionStringBuilder.with_azure_token_credential(ingest_url, creds))
        print(f"Ingesting health results from {os.path.basename(debug_file)} into {ingest_url} at {database}/{debug_table_name}")
        ingest_client.ingest_from_dataframe(df, IngestionProperties(database, debug_table_name))

def get_nhc_json_formatted_result(results_file):
    if "cpu" in results_file :
        ib_write_lb_mlx5_ib_cmd = f"cat {results_file} | grep -o 'ib_write_lb_mlx5_ib[0-7]: .*'"
        ib_write_lb_mlx5_ib_vals = os.system(ib_write_lb_mlx5_ib_cmd)
        # TO DO : organize the values from 0-7, not yet done

        stream_Copy_cmd = f"cat {results_file} | grep -o 'stream_Copy: .*'"
        stream_Copy_vals = os.system(stream_Copy_cmd)

        stream_Add_cmd = f"cat {results_file} | grep -o 'stream_Add: .*'"
        stream_Add_vals = os.system(stream_Add_cmd)

        stream_Scale_cmd = f"cat {results_file} | grep -o 'stream_Scale: .*'"
        stream_Scale_vals = os.system(stream_Scale_cmd)

        stream_Triad_cmd = f"cat {results_file} | grep -o 'stream_Triad: .*'"
        stream_Triad_vals = os.system(stream_Triad_cmd)

        data_string = ib_write_lb_mlx5_ib_vals + H2D_GPU_vals + D2H_GPU_vals + P2P_GPU_vals + nccl_all_red_vals + nccl_all_red_lb_vals

        result = {"IB_WRITE_NON_GDR": {}, "stream_Copy": {}, "stream_Add": {}, "stream_Scale": {}, "stream_Triad": {}}

        # Split the string by lines and create key-value pairs
        for line in data_string.strip().split("\n"):
            key, value = line.split(":")
            if key.startswith("ib_write_lb_mlx5_ib"):
                result["IB_WRITE_NON_GDR"][key] = float(value.strip())
            elif key.startswith("stream_Copy"):
                result["stream_Copy"]= float(value.strip())
            elif key.startswith("stream_Add"):
                result["stream_Add"]= float(value.strip())
            elif key.startswith("stream_Scale"):
                result["stream_Scale"]= float(value.strip())
            elif key.startswith("stream_Triad"):
                result["stream_Triad"]= float(value.strip())

    elif "gpu" in results_file :
        ib_write_lb_mlx5_ib_cmd = f"cat {results_file} | grep -o 'ib_write_lb_mlx5_ib[0-7]: .*'"
        ib_write_lb_mlx5_ib_vals = os.system(ib_write_lb_mlx5_ib_cmd)
        # TO DO : organize the values from 0-7, not yet done

        H2D_GPU_cmd = f"cat {results_file} | grep -o 'H2D_GPU_[0-7]: .*'"
        H2D_GPU_vals = os.system(H2D_GPU_cmd)

        D2H_GPU_cmd = f"cat {results_file} | grep -o 'D2H_GPU_[0-7]: .*'"
        D2H_GPU_vals = os.system(D2H_GPU_cmd)

        P2P_GPU_cmd = f"cat {results_file} | grep -o 'P2P_GPU_[0-7]_[0-7]: .*'"
        P2P_GPU_vals = os.system(P2P_GPU_cmd)

        nccl_all_red_cmd = f"cat {results_file} | grep -o 'nccl_all_red: .*'"
        nccl_all_red_vals = os.system(nccl_all_red_cmd)

        nccl_all_red_lb_cmd = f"cat {results_file} | grep -o 'nccl_all_red_lb: .*'"
        nccl_all_red_lb_vals = os.system(nccl_all_red_lb_cmd)


        data_string = ib_write_lb_mlx5_ib_vals + H2D_GPU_vals + D2H_GPU_vals + P2P_GPU_vals + nccl_all_red_vals + nccl_all_red_lb_vals

        result = {"IB_WRITE_GDR": {}, "GPU_BW_HTD": {}, "GPU_BW_DTH": {}, "GPU_BW_P2P": {}, "NCCL_ALL_REDUCE": {}, "NCCL_ALL_REDUCE_LOOP_BACK": {}}

        # Split the string by lines and create key-value pairs
        for line in data_string.strip().split("\n"):
            key, value = line.split(":")
            if key.startswith("ib_write_lb_mlx5_ib"):
                result["IB_WRITE_GDR"][key] = float(value.strip())
            elif key.startswith("H2D"):
                result["GPU_BW_HTD"][key] = float(value.strip())
            elif key.startswith("D2H"):
                result["GPU_BW_DTH"][key] = float(value.strip())
            elif key.startswith("P2P"):
                result["GPU_BW_P2P"][key] = float(value.strip())
            elif key.startswith("nccl_all_red"):
                result["NCCL_ALL_REDUCE"] = float(value.strip())
            elif key.startswith("nccl_all_red_lb"):
                result["NCCL_ALL_REDUCE_LOOP_BACK"] = float(value.strip())
    
def ingest_results(results_file, creds, ingest_url, database, results_table_name, hostfile=None, nhc_run_uuid="none"):
    filename_parts = os.path.basename(results_file).split("-", maxsplit=2)
    ts_str = filename_parts[2].split(".")[0]
    ts = datetime.strptime(ts_str, "%Y-%m-%d_%H-%M-%S")

    job_name = filename_parts[1]
    uuid = job_name if nhc_run_uuid == "none" else nhc_run_uuid
    uuid = f"nhc-{ts_str}-{uuid}"

    vmSize_bash_cmd = "echo $( curl -H Metadata:true --max-time 10 -s \"http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text\") | tr '[:upper:]' '[:lower:]' "
    vmSize = os.system(vmSize_bash_cmd)

    vmId_bash_cmd = "curl  -H Metadata:true --max-time 10 -s \"http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text\""
    vmId = os.system(vmId_bash_cmd)

    vmName_bash_cmd = "timeout 60 sudo /opt/azurehpc/tools/kvp_client | grep \" HostName; \"" # keep the spaces, else it will also output the results for 'PhysicalHostName'
    vmName = os.system(vmName_bash_cmd)

    phyhost = os.system("echo $(hostname) \"$(/opt/azurehpc/tools/kvp_client |grep Fully)\"")
    if not physhost:
        physhost = "not Mapped"

    with open(results_file, 'r') as f:
        full_results = file.read(results_file)
        # TO DO : Python3 compatibility issue with "file" -> "open" instead?

        jsonResult = get_nhc_json_formatted_result(results_file)
            
        record = {
            'vmSize': vmSize,
            'vmId': vmId,
            'vmHostname': vmName,
            'physHostname': physhost,
            'workflowType': "main",
            'time': ts,
            'pass': True,
            'error': '',
            'logOutput': full_results, # the entire file
            'jsonResult': jsonResult,
            'uuid': uuid
        }
        if 'error' in full_results or 'failure' in full_results:
            record['pass'] = False
            record['error'] = full_results # TO DO : go line by line to find where the error came from?


        df = pd.DataFrame(record)

        ingest_client = QueuedIngestClient(KustoConnectionStringBuilder.with_azure_token_credential(ingest_url, creds))
        print(f"Ingesting results from {os.path.basename(results_file)} into {ingest_url} at {database}/{results_table_name}")
        ingest_client.ingest_from_dataframe(df, IngestionProperties(database, results_table_name))

def parse_args():
    parser = ArgumentParser(description="Ingest NHC results into Kusto")
    parser.add_argument("health_files", nargs="+", help="List of .health.log or .debug.log files to ingest")
    parser.add_argument("--ingest_url", help="Kusto ingest URL", required=True)
    parser.add_argument("--database", help="Kusto database", required=True)
    parser.add_argument("--health_table_name", default="NodeHealthCheck", help="Kusto table name for health results")
    parser.add_argument("--debug_table_name", default="NodeHealthCheck_Debug", help="Kusto table name for debug results")
    parser.add_argument("--results_table_name", default="AzNhcRunEvents", help="Kusto table name for debug results")
    parser.add_argument("--identity", nargs="?", const=True, default=False, help="Managed Identity to use for authentication, if a client ID is provided it will be used, otherwise the system-assigned identity will be used. If --identity is not provided DefaultAzureCredentials will be used.")
    return parser.parse_args()

def get_creds(identity):
    if identity is True:
        return ManagedIdentityCredential()
    elif identity:
        return ManagedIdentityCredential(client_id=identity)
    else:
        return DefaultAzureCredential()

args = parse_args()
creds = get_creds(args.identity)

print(f"Attempting to ingest: {', '.join(args.health_files)}")
for health_file in args.health_files:
    try:
        if not os.path.exists(health_file):
            raise FileNotFoundError(f"Cannot find file '{health_file}'")

        if health_file.endswith(".health.log"):
            ingest_health_log(health_file, creds, args.ingest_url, args.database, args.health_table_name)
        elif health_file.endswith(".debug.log"):
            ingest_debug_log(health_file, creds, args.ingest_url, args.database, args.debug_table_name)
        elif health_file.endswith(".results"): # TO DO : confirm what the file should end with
            ingest_results(health_file, creds, args.ingest_url, args.database, args.results_table_name)
        else:
            # TO DO : allow all files to be uploaded?
            raise Exception("Unsupported file, must be .health.log or .debug.log produced by ./distributed_nhc.sb.sh")

    except FileNotFoundError:
        if len(health_files) == 1:
            print(f"Cannot find file '{health_file}'")
            raise
        print(f"Cannot find file '{health_file}', skipping...")