#!/bin/bash

# For NHC developers, this script is used to build the cuda or rocm runtime image for NHC

# Choices are: cuda or rocm Runtime
build_type=$1
# keep build artifacts
development=$2

if [[ -z "$development" ]]; then
    development="false"
fi

# Detect HPC-X installation directory with fallback:
# 1. Use HPCX_DIR from environment (e.g. set by 'module load mpi/hpcx')
# 2. Try loading the hpcx module
# 3. Auto-detect from /opt/hpcx-*
if [[ -z "$HPCX_DIR" ]]; then
    # Try loading the module if 'module' command is available
    if type module &>/dev/null; then
        module load mpi/hpcx 2>/dev/null
    fi
fi

if [[ -z "$HPCX_DIR" ]]; then
    # Auto-detect: pick the most recently modified hpcx directory in /opt
    HPCX_DIR=$(ls -dt /opt/hpcx-* 2>/dev/null | head -1)
fi

if [[ -z "$HPCX_DIR" || ! -d "$HPCX_DIR" ]]; then
    echo "Error: HPC-X installation not found."
    echo "Please install HPC-X, load the module ('module load mpi/hpcx'), or set HPCX_DIR."
    exit 1
fi

echo "Using HPC-X at: $HPCX_DIR"


NV_BANDWIDTH_VERSION=0.4
CUDA_ARCHITECTURES="70;80;90" 
PERF_TEST_VERSION=23.10.0-0.29
PERF_TEST_HASH=g0705c22
NCCL_VERSION=2.19.3-1
NCCL_TEST_VERSION=2.13.8

script_path="$(realpath "$0")"
parent_dir="$(dirname "$script_path")"
build_exe=${parent_dir}/build_exe
perftest_dir=$build_exe"/perftest-"${PERF_TEST_VERSION%%-*}""
nbw_dir=$build_exe"/nvbandwidth-"${NV_BANDWIDTH_VERSION}""


function build_cuda_exes(){
    # Install NV Bandwidth tool
    sudo apt install -y libboost-program-options-dev
    mkdir -p ${nbw_dir} 
    archive_url=https://github.com/NVIDIA/nvbandwidth/archive/refs/tags/v${NV_BANDWIDTH_VERSION}.tar.gz
    wget -q -O - $archive_url | tar -xz --strip=1 -C  ${nbw_dir}
    pushd ${nbw_dir}
        cmake -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc  -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} .
        make
    popd
    
    # Install NCCL
    NCCL_DOWNLOAD_URL=https://github.com/NVIDIA/nccl/archive/refs/tags/v${NCCL_VERSION}.tar.gz 
    mkdir -p nccl-${NCCL_VERSION}
    wget -q -O - ${NCCL_DOWNLOAD_URL} | tar -xz --strip=1 -C nccl-${NCCL_VERSION}
    pushd nccl-${NCCL_VERSION} 
        make -j src.build
        make pkg.debian.build #&& cd build/pkg/deb/
    popd

    # Nccl tests
    source ${HPCX_DIR}/hpcx-init.sh && hpcx_load
    mkdir -p nccl-tests
    wget -q -O - https://github.com/NVIDIA/nccl-tests/archive/refs/tags/v${NCCL_TEST_VERSION}.tar.gz | tar -xz --strip=1 -C nccl-tests
    pushd nccl-tests
        make MPI=1 MPI_HOME=${HPCX_DIR}/ompi CUDA_HOME=/usr/local/cuda
    popd

    return 0
}

# call commands from parent directory
pushd $parent_dir/../

if [[ "$build_type" == "cuda" ]]; then
    echo "Nvidia runtime selected"
    # MCR registry
    IMAGE="mcr.microsoft.com/aznhc/aznhc-nv"
    DOCK_FILE=dockerfile/azure-nvrt-nhc.dockerfile
    mkdir -p $build_exe
    pushd $build_exe
    build_cuda_exes
    popd
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
    if [[ "$development" == "false" ]]; then
        echo "Removing build artifacts"
        sudo rm -rf dockerfile/build_exe
    fi
fi

popd

exit 0
