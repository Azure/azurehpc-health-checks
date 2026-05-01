#!/bin/bash

# For NHC developers, this script is used to build the cuda or rocm runtime image for NHC
# The NVIDIA (cuda) Dockerfile uses a multi-stage build — all compilation happens inside
# the container, so no host-side CUDA toolkit or HPC-X is required for cuda builds.

# Choices are: cuda or rocm Runtime
build_type=$1

script_path="$(realpath "$0")"
parent_dir="$(dirname "$script_path")"

# call commands from parent directory
pushd $parent_dir/../

if [[ "$build_type" == "cuda" ]]; then
    echo "Nvidia runtime selected (multi-stage build, no host compilation needed)"
    IMAGE="mcr.microsoft.com/aznhc/aznhc-nv"
    DOCK_FILE=dockerfile/azure-nvrt-nhc.dockerfile
elif [[ "$build_type" == "rocm" ]]; then
    echo "AMD runtime selected"
    IMAGE="mcr.microsoft.com/aznhc/aznhc-rocm"
    DOCK_FILE=dockerfile/azure-rocm-nhc.dockerfile
else
    echo "Please specify a build type: cuda or rocm"
    exit 1
fi

sudo docker build -t $IMAGE -f $DOCK_FILE .
if [ $? -ne 0 ]; then
    echo "Failed to build docker image"
    exit 1
else
    echo "Successfully built docker image"
fi

popd

exit 0
