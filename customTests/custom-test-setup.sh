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

function check_if_command() {
    if command -v $1 &> /dev/null; then
        echo "$1"
    fi
}

# Function to find clang in specified path
function find_clang_in_path() {
    local path="$1"
	if [ ! -d "$path" ]; then
		return
	fi
    local clang_path=$(find "$path" -name "clang" | grep '/bin/')
    check_if_command "$clang_path"
}

function install_stream(){
	STREAM_DIR=${SRC_DIR}/build/stream
	mkdir -p $STREAM_DIR/
	cp ${SRC_DIR}/customTests/stream/*  $STREAM_DIR
	pushd $STREAM_DIR

	CLANG=$(find_clang_in_path "/opt/azurehpc/spack/")
	if [ -z "$CLANG" ]; then
		CLANG=$(find_clang_in_path "/opt/AMD/")
	fi
	if [ -z "$CLANG" ]; then
		CLANG=$(command -v clang)
	fi

	if [ ! -z $CLANG ] ;  then
		echo -e "clang compiler found Building Stream"
		if ! [[ -f "stream.c" ]]; then 
			wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c
		fi
		make all CC=$CLANG EXEC_DIR=$EXE_DIR
		popd
	else
		echo "clang command not found. Add clang to PATH ENV variable and rerun install script to build Stream"
		popd
		exit 1
	fi

}

if lspci | grep -iq AMD ; then
	# AMD installs
	distro=$(awk -F= '/^NAME/{print $2}' /etc/os-release)
	if [[ $distro =~ "Ubuntu" ]]; then
		sudo apt install -y rocm-bandwidth-test
	else
		sudo yum install -y rocm-bandwidth-test
	fi
else
	install_nvbandwidth
fi

install_stream
install_perf_test

exit 0
