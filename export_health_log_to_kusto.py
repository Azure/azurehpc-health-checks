#!/usr/bin/python3
import sys
import os
from datetime import datetime
from csv import DictReader
from argparse import ArgumentParser
from azure.identity import ManagedIdentityCredential
from azure.kusto.data import KustoConnectionStringBuilder
from azure.kusto.ingest import QueuedIngestClient, IngestionProperties
import pandas as pd

health_files = sys.argv[1:]

for health_file in health_files:
    try:
        if not os.path.exists(health_file):
            raise FileNotFoundError(f"Cannot find file '{health_file}'")

        # distributed_nhc-pssh-2023-07-27_02-04-52.health.log
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

            ingest_url = "https://ingest-aistresstests.centralus.kusto.windows.net"
            database = "sat13c04_stress_testdb"
            table_name = "NodeHealthCheck"

            ingest_client = QueuedIngestClient(KustoConnectionStringBuilder.with_azure_token_credential(ingest_url, creds))
            print(f"Ingesting health results from {os.path.basename(health_file)} into {ingest_url} at {database}/{table_name}")
            ingest_client.ingest_from_dataframe(df, IngestionProperties(database, table_name))
    except FileNotFoundError:
        if len(health_files) == 1:
            raise
        print("Cannot find file '{health_file}', skipping...")