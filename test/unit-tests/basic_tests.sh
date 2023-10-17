#!/bin/bash

#check NHC is installed
check_installed(){
    if [ -x "$(command -v  nhc)" ]; then
        echo "NHC exists."
        return 0
    else
        echo "NHC executable does not exist."
        return 1
    fi
}

#run NHC from Run wrapper script
#usage: runtest <expected return code> <conf file path if applicable>
# i.e. default tests: runtest 0
# test with different conf file: runtest 0 /path/to/conf/file

runtest()
{
    expected=$1
    conf=$2

    NHC_PATH=/opt/azurehpc/test/azurehpc-health-checks/run-health-checks.sh
    logpath=/tmp/nhclogfile.log
    check_installed > /dev/null
    installed=$?
    if [ "$installed" -ne "0" ]; then
        echo "NHC install check failed"
        return 1
    fi

    if [ -z "$conf" ]; then
        #test default
        sudo $NHC_PATH -o $logpath
        result=$?
    else
        sudo $NHC_PATH -c $conf -o $logpath
        result=$?
    fi
    if [ "$result" -eq "$expected" ]; then
        echo "Test passed"
        return 0
    else
        echo "Test failed"
        return 1
    fi
}
