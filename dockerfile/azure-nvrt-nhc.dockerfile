FROM nvcr.io/nvidia/cuda:12.4.1-cudnn-devel-ubuntu22.04

LABEL maintainer="azurehpc-health-checks"

SHELL ["/bin/bash", "-c"]

ENV OFED_VERSION=23.07-0.5.1.2
ENV NHC_VERSION=1.4.3
ENV AOCC_VERSION=4.0.0_1
ENV PERF_TEST_VERSION=23.10.0
ENV PERF_TEST_HASH=g0705c22
ENV NV_BANDWIDTH_VERSION=0.4
ENV NCCL_VERSION=2.19.3-1
ENV OPEN_MPI_VERSION=5.0.5
ENV NCCL_TEST_VERSION=2.13.8

ENV AZ_NHC_ROOT="/azure-nhc"
ENV MPI_BIN=/opt/openmpi/bin
ENV MPI_INCLUDE=/opt/openmpi/include
ENV MPI_LIB=/opt/openmpi/lib
ENV MPI_MAN=/opt/openmpi/share/man
ENV MPI_HOME=/opt/openmpi

WORKDIR ${AZ_NHC_ROOT}

# Disable apt caching to reduce image size
RUN echo 'DPkg::Post-Invoke { "rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin /var/lib/apt/lists/*.lz4 /var/lib/apt/lists/*Release* /var/lib/apt/lists/*Packages* /var/lib/apt/lists/*Translation* || true"; };' > /etc/apt/apt.conf.d/90docker-clean && \
    echo 'Dir::Cache::pkgcache "";' >> /etc/apt/apt.conf.d/90docker-clean && \
    echo 'Dir::Cache::srcpkgcache "";' >> /etc/apt/apt.conf.d/90docker-clean && \
    echo 'Acquire::Languages "none";' >> /etc/apt/apt.conf.d/90docker-clean

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
    bats                                        \   
    bc                                          \
    && apt-get upgrade -y

RUN mkdir -p ${AZ_NHC_ROOT}/LICENSES
COPY LICENSE ${AZ_NHC_ROOT}/LICENSES/azure-nhc_LICENSE.txt
COPY README.md ${AZ_NHC_ROOT}/README.md


# Install OFED
RUN cd /tmp && \
    wget -q https://content.mellanox.com/ofed/MLNX_OFED-${OFED_VERSION}/MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64.tgz && \
    tar xzf MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64.tgz && \
    MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64/mlnxofedinstall --user-space-only --without-fw-update --without-ucx-cuda --force && \
    rm -rf /tmp/MLNX_OFED_LINUX*


# Install OpenMPI
RUN cd /tmp && \
    wget -q "https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-${OPEN_MPI_VERSION}.tar.gz" && \
    tar -xvf openmpi-${OPEN_MPI_VERSION}.tar.gz && \
    cd openmpi-${OPEN_MPI_VERSION} && \
    cp LICENSE ${AZ_NHC_ROOT}/LICENSES/OpenMPI_LICENSE.txt && \
    ./configure --prefix=/opt/openmpi --enable-mpirun-prefix-by-default --with-platform=contrib/platform/mellanox/optimized && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/openmpi-${OPEN_MPI_VERSION} openmpi-${OPEN_MPI_VERSION}.tar.gz


# Use NCCL from the base image (already installed)
# Save the NCCL license
RUN cp /usr/share/doc/libnccl2/copyright ${AZ_NHC_ROOT}/LICENSES/nccl_LICENSE.txt || true

# Build NCCL-Tests inside the container
RUN cd /tmp && \
    wget -q -O - https://github.com/NVIDIA/nccl-tests/archive/refs/tags/v${NCCL_TEST_VERSION}.tar.gz | tar -xz && \
    cd nccl-tests-${NCCL_TEST_VERSION} && \
    make MPI=1 MPI_HOME=${MPI_HOME} CUDA_HOME=/usr/local/cuda && \
    mkdir -p /opt/nccl-tests/build && \
    cp -r build/* /opt/nccl-tests/build/ && \
    rm -rf /tmp/nccl-tests-${NCCL_TEST_VERSION}

# Install NHC
RUN cd /tmp && \
    wget -O nhc-${NHC_VERSION}.tar.xz https://github.com/mej/nhc/releases/download/${NHC_VERSION}/lbnl-nhc-${NHC_VERSION}.tar.xz  && \
    tar -xf nhc-${NHC_VERSION}.tar.xz  && \
    rm -f nhc-${NHC_VERSION}.tar.xz  && \
    cd lbnl-nhc-${NHC_VERSION}  && \
    ./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec  && \
    make test  && \
    make install && \
    mv /tmp/lbnl-nhc-${NHC_VERSION}* ${AZ_NHC_ROOT}

# Create workspace directories 
RUN mkdir -p ${AZ_NHC_ROOT}/bin && \
    mkdir -p ${AZ_NHC_ROOT}/conf && \
    mkdir -p ${AZ_NHC_ROOT}/output && \
    mkdir -p ${AZ_NHC_ROOT}/default && \
    mkdir -p ${AZ_NHC_ROOT}/default/conf && \
    mkdir -p ${AZ_NHC_ROOT}/topofiles && \
    mkdir -p ${AZ_NHC_ROOT}/lib

# Copy necessary files
COPY customTests/*.nhc /etc/nhc/scripts/
COPY conf ${AZ_NHC_ROOT}/default/conf

# Get Topofiles from AI/HPC images
RUN git clone https://github.com/Azure/azhpc-images.git /tmp/azhpc-images && \
    cp /tmp/azhpc-images/topology/* ${AZ_NHC_ROOT}/topofiles && \
    rm -rf /tmp/azhpc-images

# Install AOCC, build stream, extract libomp, then remove AOCC — all in one layer
COPY customTests/stream/Makefile /tmp/stream/
RUN cd /tmp && \
    wget https://download.amd.com/developer/eula/aocc-compiler/aocc-compiler-${AOCC_VERSION}_amd64.deb && \
    apt-get update -y && apt-get install -y ./aocc-compiler-${AOCC_VERSION}_amd64.deb && \
    rm aocc-compiler-${AOCC_VERSION}_amd64.deb && \
    cd /tmp/stream && \
    wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c && \
    make all CC=/opt/AMD/aocc-compiler-4.0.0/bin/clang EXEC_DIR=${AZ_NHC_ROOT}/bin && \
    cd ${AZ_NHC_ROOT}/LICENSES && \
    wget https://www.cs.virginia.edu/stream/FTP/Code/LICENSE.txt -O stream_LICENSE.txt && \
    cp /opt/AMD/aocc-compiler-4.0.0/lib/libomp.so ${AZ_NHC_ROOT}/lib && \
    version=$(echo "$AOCC_VERSION" | sed 's/_1$//') && \
    apt-get remove -y aocc-compiler-"${version}" && \
    apt-get autoremove -y && \
    rm -rf /tmp/stream

# Install Perf-Test
RUN mkdir -p /tmp/perftest && \
    wget -q -O - https://github.com/linux-rdma/perftest/releases/download/${PERF_TEST_VERSION}-0.29/perftest-${PERF_TEST_VERSION}-0.29.${PERF_TEST_HASH}.tar.gz | tar -xz --strip=1 -C  /tmp/perftest && \
    cd /tmp/perftest && \
    ./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h && \
    make -j$(nproc) && \
    cp ib_write_bw ${AZ_NHC_ROOT}/bin/ && \
    cp COPYING ${AZ_NHC_ROOT}/LICENSES/perftest_LICENSE && \
    rm -rf /tmp/perftest

# Install Perf-Test (non-GDR version)
RUN mkdir -p /tmp/perftest_nongdr && \
    wget -q -O - https://github.com/linux-rdma/perftest/releases/download/${PERF_TEST_VERSION}-0.29/perftest-${PERF_TEST_VERSION}-0.29.${PERF_TEST_HASH}.tar.gz | tar -xz --strip=1 -C  /tmp/perftest_nongdr && \
    cd /tmp/perftest_nongdr && \
    ./configure && \
    make -j$(nproc) && \
    cp ib_write_bw ${AZ_NHC_ROOT}/bin/ib_write_bw_nongdr && \
    rm -rf /tmp/perftest_nongdr

# Build NV Bandwidth tool inside the container
RUN cd /tmp && \
    wget -q -O - https://github.com/NVIDIA/nvbandwidth/archive/refs/tags/v${NV_BANDWIDTH_VERSION}.tar.gz | tar -xz && \
    cd nvbandwidth-${NV_BANDWIDTH_VERSION} && \
    cmake -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES="70;80;90" . && \
    make && \
    cp nvbandwidth ${AZ_NHC_ROOT}/bin/ && \
    cp LICENSE ${AZ_NHC_ROOT}/LICENSES/nvbandwidth_LICENSE && \
    rm -rf /tmp/nvbandwidth-${NV_BANDWIDTH_VERSION}

# Copy entrypoint script
COPY dockerfile/aznhc-entrypoint.sh ${AZ_NHC_ROOT}
RUN chmod +x ${AZ_NHC_ROOT}/aznhc-entrypoint.sh
