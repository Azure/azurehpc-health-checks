#!/bin/bash

function die() {
    log "ERROR:  $NAME:  Health check failed:  $*"
}

function dbg() {
    log "dbg: $*"
}

function log() {
    echo $*
}

function get_sad_path_conf(){
    SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")
    SKU="${SKU,,}"
    if echo "$SKU" | grep -q "nd96amsr_a100_v4"; then
        conf_name="nd96amsr_a100_v4"
    elif echo "$SKU" | grep -q "nd96asr_v4"; then
        conf_name="nd96asr_v4"
    elif echo "$SKU" | grep -q "nd96isr_h100_v5"; then
        conf_name="nd96isr_h100_v5"
    elif echo "$SKU" | grep -q "hb176rs_v4"; then
        conf_name="hb176rs_v4"
    elif echo "$SKU" | grep -q "nc96ads_a100_v4"; then
        conf_name="nc96ads_a100_v4"
    elif echo "$SKU" | grep -q "nd40rs_v2"; then
        conf_name="nd40rs_v2"
    else
        echo "Unit-test for this SKU $SKU is not supported" 
        return 1
    fi
    relative_path="$NHC_DIR/test/bad_test_confs/$conf_name.conf"
    echo "$(realpath -m $relative_path)"
    return 0
}

function get_topofile(){
    SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")
    SKU="${SKU,,}"
    if echo "$SKU" | grep -q "nd96amsr_a100_v4"; then
        topo_file="$NHC_DIR/customTests/topofiles/ndv4-topo.xml"
    elif echo "$SKU" | grep -q "nd96asr_v4"; then
        topo_file="$NHC_DIR/customTests/topofiles/ndv4-topo.xml"
    elif echo "$SKU" | grep -q "nd96isr_h100_v5"; then
        topo_file="$NHC_DIR/customTests/topofiles/ndv5-topo.xml"
    elif echo "$SKU" | grep -q "nc96ads_a100_v4"; then
        topo_file="$NHC_DIR/customTests/topofiles/ncv4-topo.xml"
    elif echo "$SKU" | grep -q "nd40rs_v2"; then
        topo_file="$NHC_DIR/customTests/topofiles/ndv2-topo.xml"
    else
        echo "there is no topofile for this SKU $SKU" 
        return 1
    fi
    echo "$topo_file"
    return 0
}

function get_ib_type(){
    SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")
    SKU="${SKU,,}"
    if echo "$SKU" | grep -q "nd96amsr_a100_v4" || echo "$SKU" | grep -q "nd96isr_h100_v5" || echo "$SKU" | grep -q "nd96asr_v4"  ; then
        echo "gdr"
    elif echo "$SKU" | grep -q "nd40rs_v2" || echo "$SKU" | grep -q "hb176rs_v4"; then
        echo "non_gdr"
    else
        echo "none" 
    fi
    return 0
}
