#!/bin/bash

SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")

if echo $SKU | grep "Standard_ND96asr_v4"; then
    conf_name="nd96asr_v4"
elif echo $SKU | grep "Standard_ND96amsr_A100_v4"; then
    conf_name="nd96amsr_v4"
elif echo $SKU | grep "Standard_ND96isr_v4"; then
    conf_name="nd96isr_v5"
elif echo $SKU | grep "Standard_HB120rs_v2"; then
    conf_name="hb120rs_v2"
elif echo $SKU | grep "Standard_HB120rs_v3"; then
    conf_name="hb120rs_v3"
elif echo $SKU | grep "Standard_HBv4_176"; then
    conf_name="hbv4_176"
else
    echo "SKU: $SKU check not currently implemented"
    exit 1
fi

nhc -c ./conf/$SKU.conf -l ~/logs/health.log -t 300

exit 0
