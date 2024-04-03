#!/usr/bin/python3

import socket
import subprocess
import re
 
hostname = socket.gethostname()

def get_physicalhostname():
    file_path="/opt/azurehpc/tools/kvp_client"

    proc = subprocess.Popen([file_path], stdout=subprocess.PIPE)
    output = proc.stdout.read().decode()

    pattern = r"Key: PhysicalHostName; Value: (.+)"
    match = re.search(pattern, output)
    if match:
        value = match.group(1)
        return value
 
def main():
    get_physicalhostname()
    print("{} physicalhostname = {}".format(hostname,get_physicalhostname())) 
 
if __name__ == "__main__":
    main()
    