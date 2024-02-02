FROM nvcr.io/nvidia/cuda:12.2.2-runtime-ubuntu22.04

LABEL maintainer="azurehpc-health-checks"

SHELL ["/bin/bash", "-c"]

ENV OFED_VERSION=23.07-0.5.1.2
ENV NHC_VERSION=1.4.3
ENV AOCC_VERSION=4.0.0_1
ENV PERF_TEST_VERSION=23.10.0
ENV NV_BANDWIDTH_VERSION=0.4
ENV NCCL_VERSION=2.19.3-1
ENV HPCX_VERSION=v2.16
ENV NCCL_TEST_VERSION=2.13.8

ENV AZ_NHC_ROOT="/azure-nhc"
ENV HPCX_DIR="/opt/hpcx"


WORKDIR ${AZ_NHC_ROOT}


RUN apt-get update -y                           \
    && DEBIAN_FRONTEND=noninteractive           \
    apt-get install -y                          \
    --no-install-recommends                     \
    numactl                                     \
    git                                         \
    curl                                        \
    sudo                                        \
    systemd                                     \
    wget                                        \
    libgomp1                                    \
    libcap2-bin                                 \
    cmake                                       \ 
    libpci-dev                                  \
    hwloc                                       \
    build-essential                             \        
    libboost-program-options-dev                \
    libssl-dev                                  \
    devscripts                                  \
    openssh-client                              \
    net-tools                                   \
    bc


# Install OFED
RUN cd /tmp && \
    wget -q https://content.mellanox.com/ofed/MLNX_OFED-${OFED_VERSION}/MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64.tgz && \
    tar xzf MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64.tgz && \
    MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64/mlnxofedinstall --user-space-only --without-fw-update --without-ucx-cuda --force --all && \
    rm -rf /tmp/MLNX_OFED_LINUX*

# install clang dependency
RUN cd /tmp && \
    wget https://download.amd.com/developer/eula/aocc-compiler/aocc-compiler-${AOCC_VERSION}_amd64.deb && \
    apt install -y ./aocc-compiler-${AOCC_VERSION}_amd64.deb && \
    rm aocc-compiler-${AOCC_VERSION}_amd64.deb

# Install HPCx
RUN cd /tmp && \
    TARBALL="hpcx-${HPCX_VERSION}-gcc-mlnx_ofed-ubuntu22.04-cuda12-gdrcopy2-nccl2.18-x86_64.tbz" && \
    HPCX_DOWNLOAD_URL=https://content.mellanox.com/hpc/hpc-x/${HPCX_VERSION}/${TARBALL} && \
    HPCX_FOLDER=$(basename ${HPCX_DOWNLOAD_URL} .tbz) && \
    mkdir -p $HPCX_FOLDER && \
    wget -q ${HPCX_DOWNLOAD_URL} && \
    tar -xvf ${TARBALL} && \
    mv ${HPCX_FOLDER} ${HPCX_DIR} && \
    rm -rf /tmp/${TARBALL}

# Install NCCL
ARG host_nccl_dir=dockerfile/build_exe/nccl-${NCCL_VERSION}
RUN mkdir -p /opt/nccl
COPY ${host_nccl_dir} /opt/nccl
RUN cd /opt/nccl/build/pkg/deb/ && \
    dpkg -i libnccl2_${NCCL_VERSION}+cuda12.2_amd64.deb && \
    dpkg -i libnccl-dev_${NCCL_VERSION}+cuda12.2_amd64.deb && \
    rm -rf /opt/nccl


# Install NCCL-Test
ARG host_nccl_test_dir=dockerfile/build_exe/nccl-tests
COPY ${host_nccl_test_dir} /opt/nccl-tests

# Install NHC
RUN cd /tmp && \
    wget -O nhc-${NHC_VERSION}.tar.xz https://github.com/mej/nhc/releases/download/${NHC_VERSION}/lbnl-nhc-${NHC_VERSION}.tar.xz  && \
    tar -xf nhc-${NHC_VERSION}.tar.xz  && \
    rm -f nhc-${NHC_VERSION}.tar.xz  && \
    cd lbnl-nhc-${NHC_VERSION}  && \
    ./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec  && \
    make test  && \
    make install && \
    rm -rf /tmp/lbnl-nhc-${NHC_VERSION}*

# Create workspace directories 
RUN mkdir -p ${AZ_NHC_ROOT}/bin
RUN mkdir -p ${AZ_NHC_ROOT}/conf
RUN mkdir -p ${AZ_NHC_ROOT}/output

# Copy necessary files
COPY customTests/*.nhc /etc/nhc/scripts/
COPY customTests/topofiles ${AZ_NHC_ROOT}/topofiles

# Install stream 
RUN mkdir -p /tmp/stream
COPY customTests/stream/Makefile /tmp/stream/
RUN cd /tmp/stream && \
wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c  && \
make all CC=/opt/AMD/aocc-compiler-4.0.0/bin/clang EXEC_DIR=${AZ_NHC_ROOT}/bin && \
rm -rf /tmp/stream

# Copy necessary files
COPY customTests/*.nhc /etc/nhc/scripts/
COPY customTests/topofiles ${AZ_NHC_ROOT}/topofiles

# Install Perf-Test
ARG host_perftest_dir=dockerfile/build_exe/perftest-${PERF_TEST_VERSION}
COPY ${host_perftest_dir}/ib_write_bw ${AZ_NHC_ROOT}/bin
COPY ${host_perftest_dir}_nongdr/ib_write_bw ${AZ_NHC_ROOT}/bin/ib_write_bw_nongdr

# Install NV Bandwidth tool
ARG host_nvbandwidth_dir=dockerfile/build_exe/nvbandwidth-${NV_BANDWIDTH_VERSION}
COPY ${host_nvbandwidth_dir}/nvbandwidth ${AZ_NHC_ROOT}/bin


# Copy entrypoint script
COPY dockerfile/aznhc-entrypoint.sh ${AZ_NHC_ROOT}
RUN chmod +x ${AZ_NHC_ROOT}/aznhc-entrypoint.sh
