#!/bin/bash

# For NHC developers, this script is used to build the cuda, cuda-arm, or rocm runtime image for NHC
# The NVIDIA (cuda/cuda-arm) Dockerfiles use a multi-stage build — all compilation happens inside
# the container, so no host-side CUDA toolkit or HPC-X is required for cuda builds.

# Choices are: cuda, cuda-arm, or rocm Runtime
build_type=$1

# On an aarch64 host, default a plain "cuda" request to "cuda-arm" for convenience
if [[ -z "$build_type" || "$build_type" == "cuda" ]] && [[ "$(uname -m)" == "aarch64" ]]; then
    echo "aarch64 host detected, defaulting to cuda-arm build"
    build_type="cuda-arm"
fi

script_path="$(realpath "$0")"
parent_dir="$(dirname "$script_path")"

# call commands from parent directory
pushd $parent_dir/../

if [[ "$build_type" == "cuda" ]]; then
    echo "Nvidia runtime selected (multi-stage build, no host compilation needed)"
    IMAGE="mcr.microsoft.com/aznhc/aznhc-nv"
    DOCK_FILE=dockerfile/azure-nvrt-nhc.dockerfile
elif [[ "$build_type" == "cuda-arm" ]]; then
    echo "Nvidia aarch64 (Grace/Blackwell) runtime selected (multi-stage build, no host compilation needed)"
    IMAGE="mcr.microsoft.com/aznhc/aznhc-nv:aarch64"
    DOCK_FILE=dockerfile/azure-nvrt-nhc-aarch64.dockerfile
elif [[ "$build_type" == "rocm" ]]; then
    echo "AMD runtime selected"
    IMAGE="mcr.microsoft.com/aznhc/aznhc-rocm"
    DOCK_FILE=dockerfile/azure-rocm-nhc.dockerfile
else
    echo "Please specify a build type: cuda, cuda-arm, or rocm"
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
