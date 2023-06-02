#!/bin/bash

SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")
echo "Running health checks for $SKU SKU..."

if [ "${SKU,,}" = "standard_nd96asr_v4" ]; then
    conf_name="nd96asr_v4"
elif [ "${SKU,,}" = "standard_nd96amsr_a100_v4" ]; then
    conf_name="nd96amsr_v4"
elif [ "${SKU,,}" = "standard_nd96isr_h100_v5" ]; then
    conf_name="nd96isr_v5"
elif [ "${SKU,,}" = "standard_hb120rs_v2" ]; then
    conf_name="hb120rs_v2"
elif [ "${SKU,,}" = "standard_hb120rs_v3" ]; then
    conf_name="hb120rs_v3"
elif [ "${SKU,,}" = "standard_hbv4_176" ]; then
    conf_name="hbv4_176"
elif [ "${SKU,,}" = "standard_hx176rs" ]; then
    conf_name="hx176rs_4"
else
    echo "SKU: $SKU check not currently implemented"
    exit 1
fi

log_path="${1:-$(pwd)/health.log}"

nhc CONFFILE=./conf/$conf_name.conf LOGFILE=$log_path TIMEOUT=300

exit 0
