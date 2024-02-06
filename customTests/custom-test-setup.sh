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

	if [ -f $CUDA_DIR/include/cuda.h  ]; then
		./configure CUDA_H_PATH=$CUDA_DIR/include/cuda.h  --exec-prefix=${INSTALL_DIR}
	else
		./configure --exec-prefix=${INSTALL_DIR}
	fi

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

function install_stream(){
	STREAM_DIR=${SRC_DIR}/build/stream
	mkdir -p $STREAM_DIR/
	cp ${SRC_DIR}/customTests/stream/*  $STREAM_DIR
	pushd $STREAM_DIR

	# Stream
	if command -v /opt/AMD/aocc-compiler-4.0.0/bin/clang &> /dev/null || command -v clang &> /dev/null; then
		echo -e "clang compiler found Building Stream"

		if ! [[ -f "stream.c" ]]; then 
			wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c
		fi
		if command -v /opt/AMD/aocc-compiler-4.0.0/bin/clang &> /dev/null; then
			make all CC=/opt/AMD/aocc-compiler-4.0.0/bin/clang EXEC_DIR=$EXE_DIR
		else
			make all CC=clang EXEC_DIR=$EXE_DIR
		fi
		popd
	else
		echo "clang command not found. Skipping Stream build. Add clang to PATH ENV variable and rerun script to build Stream"
	fi
}

#Nvidia installs
if lspci | grep -iq NVIDIA ; then
	install_nvbandwidth
elif lspci | grep -iq AMD ; then
	# AMD installs
	distro=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
	if [[ $distro =~ "Ubuntu" ]]; then
		sudo apt install -y rocm-bandwidth-test
	else
		sudo yum install -y rocm-bandwidth-test
	fi
fi

install_stream
install_perf_test

exit 0
