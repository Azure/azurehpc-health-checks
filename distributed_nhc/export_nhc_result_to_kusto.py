#!/usr/bin/python3
import sys
import os
from datetime import datetime
from csv import DictReader
from argparse import ArgumentParser
from azure.identity import ManagedIdentityCredential, DefaultAzureCredential
from azure.kusto.data import KustoConnectionStringBuilder
from azure.kusto.ingest import QueuedIngestClient, IngestionProperties
import pandas as pd

ingest_url = "https://ingest-aistresstests.centralus.kusto.windows.net"
database = "sat13c04_stress_testdb"
health_table_name = "NodeHealthCheck"
debug_table_name = "NodeHealthCheck_Debug"

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

        creds = ManagedIdentityCredential(
            client_id = "16b52144-5ca5-4c25-aac5-0d3b7a4cb36d"
        )

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

    with open(health_file, 'r') as f:
        lines = f.readlines()
        reader = DictReader(lines, fieldnames = ["Hostname", "DebugLog"], delimiter='|', restkey="extra")

        df = pd.DataFrame(reader)
        df['Timestamp'] = ts
        df['JobName'] = job_name
        df['NodeName'] = df.apply(lambda x: x['Hostname'].strip(), axis=1)
        df['DebugLog'] = df.apply(lambda x: x['DebugLog'].strip(), axis=1)
        df = df[['Timestamp', 'JobName', 'Hostname', 'DebugLog']]

        creds = ManagedIdentityCredential(
            client_id = "16b52144-5ca5-4c25-aac5-0d3b7a4cb36d"
        )

        ingest_client = QueuedIngestClient(KustoConnectionStringBuilder.with_azure_token_credential(ingest_url, creds))
        print(f"Ingesting health results from {os.path.basename(debug_file)} into {ingest_url} at {database}/{debug_table_name}")
        ingest_client.ingest_from_dataframe(df, IngestionProperties(database, debug_table_name))

health_files = sys.argv[1:]

def parse_args():
    parser = ArgumentParser(description="Ingest NHC results into Kusto")
    parser.add_argument("health_files", nargs="+", help="List of .health.log or .debug.log files to ingest")
    parser.add_argument("--ingest_url", help="Kusto ingest URL", required=True)
    parser.add_argument("--database", help="Kusto database", required=True)
    parser.add_argument("--health_table_name", default="NodeHealthCheck", help="Kusto table name for health results")
    parser.add_argument("--debug_table_name", default="NodeHealthCheck_Debug", help="Kusto table name for debug results")
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
        else:
            raise Exception("Unsuported file, must be .health.log or .debug.log produced by ./distributed_nhc.sb.sh")

    except FileNotFoundError:
        if len(health_files) == 1:
            print(f"Cannot find file '{health_file}'")
            raise
        print(f"Cannot find file '{health_file}', skipping...")