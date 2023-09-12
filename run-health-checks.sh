#!/bin/bash

SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")

log_path="${1:-./health.log}"
log_path=$(realpath "$log_path")

echo "Running health checks for $SKU SKU..."

SKU="${SKU,,}"
if echo "$SKU" | grep -q "nd96asr_v4"; then
    conf_name="nd96asr_v4"
elif echo "$SKU" | grep -q "nd96amsr_a100_v4"; then
    conf_name="nd96amsr_a100_v4"
elif echo "$SKU" | grep -q "nd96isr_h100_v5"; then
    conf_name="nd96isr_h100_v5"
elif echo "$SKU" | grep -q "hb120rs_v2"; then
    conf_name="hb120rs_v2"
elif echo "$SKU" | grep -q "hb120rs_v3"; then
    conf_name="hb120rs_v3"
elif echo "$SKU" | grep -q "hb176rs_v4"; then
    conf_name="hb176rs_v4"
elif  echo "$SKU" | grep -q "hb176-144rs_v4"; then
    conf_name="hb176-144rs_v4"
elif  echo "$SKU" | grep -q "hb176-96rs_v4"; then
    conf_name="hb176-96rs_v4"
elif  echo "$SKU" | grep -q "hb176-48rs_v4"; then
    conf_name="hb176-48rs_v4"
elif  echo "$SKU" | grep -q "hb176-24rs_v4"; then
    conf_name="hb176-24rs_v4"
elif echo "$SKU" | grep -q "hx176rs"; then
    conf_name="hx176rs"
elif  echo "$SKU" | grep -q "hx176-144rs"; then
    conf_name="hx176-144rs"
elif  echo "$SKU" | grep -q "hx176-96rs"; then
    conf_name="hx176-96rs"
elif  echo "$SKU" | grep -q "hx176-48rs"; then
    conf_name="hx176-48rs"
elif  echo "$SKU" | grep -q "hx176-24rs"; then
    conf_name="hx176-24rs"
else
    echo "The vm SKU '$SKU' is currently not supported by Azure health checks." | tee -a $log_path
    exit 0
fi

#add accelerated network if applicable
NHC_DIR=$(dirname "${BASH_SOURCE[0]}")
acc_file="$NHC_DIR/conf/$conf_name.conf"
acc_net=$(ibstatus mlx5_an0)
if [ $? -eq 0 ] && ! grep -q 'check_hw_ib 40 mlx5_an0:1' "$acc_file"; then
	echo -e "\n\n### Accelerate network check\n * || check_hw_ib 40 mlx5_an0:1\n * || check_hw_eth eth1">> $acc_file
fi

#nhc CONFFILE=$NHC_DIR/conf/$conf_name.conf LOGFILE=$log_path TIMEOUT=500
