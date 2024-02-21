#!/usr/bin/python3
import sys
import os
import json
import re
import subprocess
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

    with open(debug_file, 'r') as f:
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

def run_command(cmd):
    result = subprocess.run(cmd, capture_output=True, shell=True, text=True)
    return result.stdout.strip()

def get_nhc_json_formatted_result(results_file):
    def natural_sort_key(s):
        return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', s)]

    # check if GPU or CPU
    processor_cmd = f"lspci | grep -iq NVIDIA" # if not empty, then GPU
    processor_str = run_command(processor_cmd)

    processor = "GPU" if processor_str else "CPU"

    if processor == "GPU":
        ib_write_lb_mlx5_ib_cmd = f"cat {results_file} | grep -o 'ib_write_lb_mlx5_ib[0-7]: .*'"
        ib_write_lb_mlx5_ib_str = run_command(ib_write_lb_mlx5_ib_cmd)
        ib_write_lb_mlx5_ib_str = sorted(ib_write_lb_mlx5_ib_str.strip().split("\n"), key=natural_sort_key)
        ib_write_lb_mlx5_ib_str = '\n'.join(ib_write_lb_mlx5_ib_str) # convert to string

        H2D_GPU_cmd = f"cat {results_file} | grep -o 'H2D_GPU_[0-7]: .*'"
        H2D_GPU_str = run_command(H2D_GPU_cmd)

        D2H_GPU_cmd = f"cat {results_file} | grep -o 'D2H_GPU_[0-7]: .*'"
        D2H_GPU_str = run_command(D2H_GPU_cmd)

        P2P_GPU_cmd = f"cat {results_file} | grep -o 'P2P_GPU_[0-7]_[0-7]: .*'"
        P2P_GPU_str = run_command(P2P_GPU_cmd)

        nccl_all_red_cmd = f"cat {results_file} | grep -o 'nccl_all_red: .*'"
        nccl_all_red_str = run_command(nccl_all_red_cmd)

        nccl_all_red_lb_cmd = f"cat {results_file} | grep -o 'nccl_all_red_lb: .*'"
        nccl_all_red_lb_str = run_command(nccl_all_red_lb_cmd)

        data_string = "\n".join([ib_write_lb_mlx5_ib_str, H2D_GPU_str, D2H_GPU_str, P2P_GPU_str, nccl_all_red_str, nccl_all_red_lb_str])
        data_string = os.linesep.join([s for s in data_string.splitlines() if s]) # remove empty lines
        result = {"IB_WRITE_GDR": {}, "GPU_BW_HTD": {}, "GPU_BW_DTH": {}, "GPU_BW_P2P": {}, "NCCL_ALL_REDUCE": {}, "NCCL_ALL_REDUCE_LOOP_BACK": {}}

        # Split the string by lines and create key-value pairs
        for line in data_string.strip().split("\n"):
            if line.isspace():
                continue
            key, value = line.split(":")
            if key.startswith("ib_write_lb_mlx5_ib"):
                result["IB_WRITE_GDR"][key] = str(value.strip())
            elif key.startswith("H2D"):
                result["GPU_BW_HTD"][key] = str(value.strip())
            elif key.startswith("D2H"):
                result["GPU_BW_DTH"][key] = str(value.strip())
            elif key.startswith("P2P"):
                result["GPU_BW_P2P"][key] = str(value.strip())
            elif key.startswith("nccl_all_red_lb"):
                result["NCCL_ALL_REDUCE_LOOP_BACK"] = str(value.strip())
            elif key.startswith("nccl_all_red"):
                result["NCCL_ALL_REDUCE"] = str(value.strip())

    else: # processor == "CPU"
        ib_write_lb_mlx5_ib_cmd = f"cat {results_file} | grep -o 'ib_write_lb_mlx5_ib[0-7]: .*'"
        ib_write_lb_mlx5_ib_str = run_command(ib_write_lb_mlx5_ib_cmd)
        ib_write_lb_mlx5_ib_str = sorted(ib_write_lb_mlx5_ib_str.strip().split("\n"), key=natural_sort_key)
        ib_write_lb_mlx5_ib_str = '\n'.join(ib_write_lb_mlx5_ib_str) # convert to string

        stream_Copy_cmd = f"cat {results_file} | grep -o 'stream_Copy: .*'"
        stream_Copy_str = run_command(stream_Copy_cmd)

        stream_Add_cmd = f"cat {results_file} | grep -o 'stream_Add: .*'"
        stream_Add_str = run_command(stream_Add_cmd)

        stream_Scale_cmd = f"cat {results_file} | grep -o 'stream_Scale: .*'"
        stream_Scale_str = run_command(stream_Scale_cmd)

        stream_Triad_cmd = f"cat {results_file} | grep -o 'stream_Triad: .*'"
        stream_Triad_str = run_command(stream_Triad_cmd)

        data_string = "\n".join([ib_write_lb_mlx5_ib_str, stream_Copy_str, stream_Add_str, stream_Scale_str, stream_Triad_str])
        data_string = os.linesep.join([s for s in data_string.splitlines() if s]) # remove empty lines
        result = {"IB_WRITE_NON_GDR": {}, "stream_Copy": {}, "stream_Add": {}, "stream_Scale": {}, "stream_Triad": {}}

        # Split the string by lines and create key-value pairs
        for line in data_string.strip().split("\n"):
            if line.isspace():
                continue
            key, value = line.split(":")
            if key.startswith("ib_write_lb_mlx5_ib"):
                result["IB_WRITE_NON_GDR"][key] = str(value.strip())
            elif key.startswith("stream_Copy"):
                result["stream_Copy"]= str(value.strip())
            elif key.startswith("stream_Add"):
                result["stream_Add"]= str(value.strip())
            elif key.startswith("stream_Scale"):
                result["stream_Scale"]= str(value.strip())
            elif key.startswith("stream_Triad"):
                result["stream_Triad"]= str(value.strip())
    
    return result

def ingest_results(results_file, creds, ingest_url, database, results_table_name, nhc_run_uuid="None"):
    ts = datetime.now().strftime("%Y-%m-%d_%H-%M-%S")

    job_name = results_file.replace("\\", "/").split(".")[0].split("/")[-1] # account for \ or / in path
    uuid = job_name if nhc_run_uuid == "None" else f"{nhc_run_uuid}-{job_name}"
    if uuid == "health":
        uuid = ""
    else :
        uuid = "-" + uuid # add the dash here instead of below; this way if 'uuid' is empty, we don't have a trailing dash
    full_uuid = f"nhc-{ts}{uuid}"

    vmSize_bash_cmd = "echo $( curl -H Metadata:true --max-time 10 -s \"http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text\") | tr '[:upper:]' '[:lower:]' "
    vmSize = run_command(vmSize_bash_cmd)

    vmId_bash_cmd = "curl  -H Metadata:true --max-time 10 -s \"http://169.254.169.254/metadata/instance/compute/vmId?api-version=2021-02-01&format=text\""
    vmId = run_command(vmId_bash_cmd)

    vmName_bash_cmd = "hostname"
    vmName = run_command(vmName_bash_cmd)

    physhost = run_command("echo $(hostname) \"$(/opt/azurehpc/tools/kvp_client | grep Fully)\" | cut -d ':' -f 3 | cut -d ' ' -f 2 | sed 's/\"//g'")
    if not physhost:
        physhost = "not Mapped"

    with open(results_file, 'r') as f:
        full_results = f.read()
        jsonResultDict = get_nhc_json_formatted_result(results_file)
        jsonResult = json.dumps(jsonResultDict)

        record = {
            'vmSize': vmSize,
            'vmId': vmId,
            'vmHostname': vmName,
            'physHostname': physhost,
            'workflowType': "main",
            'time': ts,
            'pass': False, # keep as default false
            'errors': '',
            'logOutput': full_results, # the entire file
            'jsonResult': jsonResult,
            'uuid': full_uuid
        }

        if "ERROR" in full_results:
            record['pass'] = False
            record['errors'] = full_results
        elif "Node Health Check completed successfully" in full_results:
            record['pass'] = True
        else:
            record['pass'] = False
            record['errors'] = "No Node Health Check completed successfully or ERROR"

        df = pd.DataFrame(record, index=[0])

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
    parser.add_argument("--results_table_name", default="AzNhcRunEvents", help="Kusto table name for results")
    parser.add_argument("--uuid", default="None", help="UUID to help identify results in Kusto table")
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
        elif health_file.endswith(".log"):
            ingest_results(health_file, creds, args.ingest_url, args.database, args.results_table_name, args.uuid)
        else:
            raise Exception("Unsupported file, must be .health.log or .debug.log produced by ./distributed_nhc.sb.sh, or .log produced by run-health-checks.sh")

    except FileNotFoundError:
        if len(args.health_files) == 1:
            print(f"Cannot find file '{health_file}'")
            raise
        print(f"Cannot find file '{health_file}', skipping...")