#! /bin/bash

CONF_FILE=${AZ_NHC_ROOT}/conf/aznhc.conf
OUTPUT_PATH=${AZ_NHC_ROOT}/output/aznhc.log

cp ${AZ_NHC_ROOT}/customTests/*.nhc /etc/nhc/scripts/

if [ -z "$TIMEOUT" ]; then
    TIMEOUT=500
fi

if [ "${#NHC_ARGS[@]}" -eq 0 ]; then
    nhc CONFFILE=$CONF_FILE LOGFILE=$OUTPUT_PATH TIMEOUT=$TIMEOUT
else
    nhc ${NHC_ARGS[@]} CONFFILE=$CONF_FILE LOGFILE=$OUTPUT_PATH TIMEOUT=$TIMEOUT
fi
