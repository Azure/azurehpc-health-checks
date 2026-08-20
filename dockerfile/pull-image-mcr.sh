#!/bin/bash

# Choices are: cuda, cuda-arm, or rocm Runtime
build_type=$1

if [[ -z "$build_type" ]]; then
    if [[ "$(uname -m)" == "aarch64" ]]; then
        build_type="cuda-arm"
    else
        build_type="cuda"
    fi
fi

if [[ "$build_type" == "cuda" ]]; then
    DOCK_IMG_NAME="mcr.microsoft.com/aznhc/aznhc-nv"
elif [[ "$build_type" == "cuda-arm" ]]; then
    DOCK_IMG_NAME="mcr.microsoft.com/aznhc/aznhc-nv:aarch64"
elif [[ "$build_type" == "rocm" ]]; then
    DOCK_IMG_NAME="mcr.microsoft.com/aznhc/aznhc-rocm"
else
    echo "Please specify a build type: cuda, cuda-arm, or rocm"
    exit 1
fi

sudo docker pull $DOCK_IMG_NAME
