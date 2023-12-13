#!/bin/bash

INSTALL_DIR=$1
CUDA_DIR=$2

EXE_DIR=$INSTALL_DIR/bin
SRC_DIR=$(dirname "${BASH_SOURCE[0]}")/../

# https://developer.nvidia.com/cuda-gpus for V100, A100, H100
CUDA_ARCHITECTURES="70;80;90" 

# location where we will be putting execuatble. Must match custom tests.
if [[ -z "$EXE_DIR" ]];then
	EXE_DIR=/opt/azurehpc/test/nhc
fi

if [[ -z "$CUDA_DIR" ]];then
	CUDA_DIR=/usr/local/cuda
fi

mkdir -p $EXE_DIR

function install_perf_test(){
	# create perf-test executables
	echo -e "Building PerfTest"

	VERSION=4.5-0.12
	VERSION_HASH=ge93c538

	pushd ${SRC_DIR}/build

	perftest_dir="perftest-"${VERSION%%-*}""
	mkdir -p ${perftest_dir}
	archive_url="https://github.com/linux-rdma/perftest/releases/download/v${VERSION}/perftest-${VERSION}.${VERSION_HASH}.tar.gz"
	wget -q -O - $archive_url | tar -xz --strip=1 -C  ${perftest_dir}

	pushd ${perftest_dir} 
	./configure CUDA_H_PATH=$CUDA_DIR/include/cuda.h  --exec-prefix=${INSTALL_DIR}

	make
	make install
	echo "Perf-Test version: $VERSION" >> $AZ_NHC_VERSION_LOG
	popd
	popd
}

function install_nvbandwidth(){
	# NVBW Test Setup
	pushd $SRC_DIR/build
	git clone https://github.com/NVIDIA/nvbandwidth.git nvbandwidth
	pushd nvbandwidth
	$NHC_CMAKE -DCMAKE_CUDA_COMPILER=$CUDA_DIR/bin/nvcc  -DCMAKE_CUDA_ARCHITECTURES="$CUDA_ARCHITECTURES" .
	make
	cp nvbandwidth $EXE_DIR
	VERSION=$(git describe --tags --abbrev=0 2>/dev/null)
	if [ $? == 0 ]; then
		echo "NVBandwidth version: $VERSION" >> $AZ_NHC_VERSION_LOG
	else
		echo "NVBandwidth version: Main branch" >> $AZ_NHC_VERSION_LOG
	fi
	popd
	popd
}

#Nvidia installs
if lspci | grep -iq NVIDIA ; then
	install_nvbandwidth
else
	# Stream
	if command -v /opt/AMD/aocc-compiler-4.0.0/bin/clang &> /dev/null || command -v clang &> /dev/null; then
		echo -e "clang compiler found Building Stream"
		pushd ${SRC_DIR}/stream
		if ! [[ -f "stream.c" ]]; then 
			wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c
		fi

		HB_HX_SKUS="standard_hb176rs_v4|standard_hb176-144rs_v4|standard_hb176-96rs_v4|standard_hb176-48rs_v4|standard_hb176-24rs_v4|standard_hx176rs|standard_hx176-144rs|standard_hx176-96rs|standard_hx176-48rs|standard_hx176-24rs"
		SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text")
		SKU=$(echo "$SKU" | tr '[:upper:]' '[:lower:]')

		if [[ "$HB_HX_SKUS" =~ "$SKU"  ]]; then
			BUILD=ZEN4
		elif echo $SKU | grep "hb120rs_v3"; then
			BUILD=ZEN3
		elif echo $SKU | grep "hb120rs_v2"; then
			BUILD=ZEN2
		else
			#default to zen3 build
			BUILD=ZEN3
		fi

		if command -v /opt/AMD/aocc-compiler-4.0.0/bin/clang &> /dev/null; then
			make $BUILD CC=/opt/AMD/aocc-compiler-4.0.0/bin/clang EXEC_DIR=$EXE_DIR
		else
			make $BUILD CC=clang EXEC_DIR=$EXE_DIR
		fi
		popd
	else
		echo "clang command not found. Skipping Stream build. Add clang to PATH ENV variable and rerun script to build Stream"
	fi
fi

install_perf_test

exit 0
