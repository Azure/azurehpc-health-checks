#!/bin/bash

SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")
echo "Running health checks for $SKU SKU..."

SKU="${SKU,,}"
if echo "$SKU" | grep -q "nd96asr_v4"; then
    conf_name="nd96asr_v4"
elif echo "$SKU" | grep -q "nd96amsr_a100_v4"; then
    conf_name="nd96amsr_v4"
elif echo "$SKU" | grep -q "nd96isr_h100_v5"; then
    conf_name="nd96isr_v5"
elif echo "$SKU" | grep -q "hb120rs_v2"; then
    conf_name="hb120rs_v2"
elif echo "$SKU" | grep -q "hb120rs_v3"; then
    conf_name="hb120rs_v3"
elif echo "$SKU" | grep -q "hb176rs_v4"; then
    conf_name="hbv4_176"
elif echo "$SKU" | grep -q "hx176rs"; then
    conf_name="hx176rs_4"
else
    echo "SKU health check not currently implemented"
    exit 1
fi

log_path="${1:-./health.log}"
log_path=$(realpath "$log_path")

nhc CONFFILE=./conf/$conf_name.conf LOGFILE=$log_path TIMEOUT=300
