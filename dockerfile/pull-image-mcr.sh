#!/bin/bash

# Choices are: cuda or rocm Runtime
build_type=$1

if [[ -z "$build_type" ]]; then
    build_type="cuda"
fi

if [[ "$build_type" == "cuda" ]]; then
    DOCK_IMG_NAME="mcr.microsoft.com/aznhc/aznhc-nv"
elif [[ "$build_type" == "rocm" ]]; then
    DOCK_IMG_NAME="mcr.microsoft.com/aznhc/aznhc-rocm"
else
    echo "Please specify a build type: cuda or rocm"
    exit 1
fi

sudo docker pull $DOCK_IMG_NAME
