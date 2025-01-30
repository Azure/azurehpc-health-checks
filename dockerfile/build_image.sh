#!/bin/bash

# For NHC developers, this script is used to build the cuda or rocm runtime image for NHC

# Choices are: cuda or rocm Runtime
build_type=$1
# keep build artifacts
development=$2

if [[ -z "$development" ]]; then
    development="false"
fi

# Set this to the right path
HPCX_MPI_DIR=/opt/hpcx-v2.18-gcc-mlnx_ofed-ubuntu22.04-cuda12-x86_64

if [[ ! -d $HPCX_MPI_DIR ]]; then
    echo "HPCX_MPI_DIR: $HPCX_MPI_DIR not found. Please install HPC-X"
    exit 1
fi


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

    # Install Perf-Test
    mkdir -p ${perftest_dir}
    archive_url=https://github.com/linux-rdma/perftest/releases/download/${PERF_TEST_VERSION}/perftest-${PERF_TEST_VERSION}.${PERF_TEST_HASH}.tar.gz 
    wget -q -O - $archive_url | tar -xz --strip=1 -C  ${perftest_dir} 
    pushd ${perftest_dir} 
        ./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h
        make
    popd

    mkdir -p ${perftest_dir}_nongdr
    archive_url=https://github.com/linux-rdma/perftest/releases/download/${PERF_TEST_VERSION}/perftest-${PERF_TEST_VERSION}.${PERF_TEST_HASH}.tar.gz 
    wget -q -O - $archive_url | tar -xz --strip=1 -C  ${perftest_dir}_nongdr
    pushd ${perftest_dir}_nongdr
        ./configure
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
    source ${HPCX_MPI_DIR}/hpcx-init.sh && hpcx_load
    mkdir -p nccl-tests
    wget -q -O - https://github.com/NVIDIA/nccl-tests/archive/refs/tags/v${NCCL_TEST_VERSION}.tar.gz | tar -xz --strip=1 -C nccl-tests
    pushd nccl-tests
        make MPI=1 MPI_HOME=${HPCX_MPI_DIR} CUDA_HOME=/usr/local/cuda
    popd

    return 0
}

# call commands from parent directory
pushd $parent_dir/../

if [[ "$build_type" == "cuda" ]]; then
    echo "Nvidia runtime selected"
    # ACR registry
    IMAGE="azurenodehealthchecks.azurecr.io/public/aznhc/aznhc-nv"
    DOCK_FILE=dockerfile/azure-nvrt-nhc.dockerfile
    mkdir -p $build_exe
    pushd $build_exe
    build_cuda_exes
    popd
elif [[ "$build_type" == "rocm" ]]; then
    echo "AMD runtime selected"
    IMAGE="azurenodehealthchecks.azurecr.io/staging/aznhc/aznhc-rocm"
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
