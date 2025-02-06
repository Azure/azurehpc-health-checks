#!/bin/bash

# Usage:
# ./pull_image.sh [cuda|rocm]
#
# Defaults to "cuda" if no argument is provided.

build_type=$1

if [[ -z "$build_type" ]]; then
    build_type="cuda"
fi

if [[ "$build_type" == "cuda" ]]; then
    DOCK_IMG_NAME="mcr.microsoft.com/aznhc/aznhc-nv"
elif [[ "$build_type" == "rocm" ]]; then
    echo "Rocm is not supported yet but coming soon"
    exit 1
else
    echo "Please specify a build type: cuda or rocm"
    exit 1
fi

# Check if containerd (ctr) is available
if command -v ctr &> /dev/null; then
    echo "containerd found. Pulling with containerd..."
    if ! sudo ctr images pull "$DOCK_IMG_NAME"; then
        echo "Failed to pull image with containerd"
        exit 1
    fi
else
    echo "containerd not found. Falling back to Docker..."
    if ! sudo docker pull "$DOCK_IMG_NAME"; then
        echo "Failed to pull image with Docker"
        exit 1
    fi
fi
