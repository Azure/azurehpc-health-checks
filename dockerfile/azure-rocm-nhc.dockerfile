from rocm/dev-ubuntu-22.04:6.1

LABEL maintainer="azurehpc-health-checks"

SHELL ["/bin/bash", "-c"]

ENV OFED_VERSION=23.07-0.5.1.2
ENV OPEN_MPI_VERSION=4.1.5
ENV NHC_VERSION=1.4.3

ENV AZ_NHC_ROOT="/azure-nhc"
ENV MPI_BIN=/opt/openmpi/bin
ENV MPI_INCLUDE=/opt/openmpi/include
ENV MPI_LIB=/opt/openmpi/lib
ENV MPI_MAN=/opt/openmpi/share/man
ENV MPI_HOME=/opt/openmpi
ENV PATH=${MPI_BIN}:${PATH}
ENV PERF_TEST_VERSION=23.10.0-0.29
ENV PERF_TEST_HASH=g0705c22

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
    bats                                        \
    rocm-bandwidth-test                         \
    cmake                                       \ 
    bc

# Create workspace directories 
RUN mkdir -p ${AZ_NHC_ROOT}/bin && \
    mkdir -p ${AZ_NHC_ROOT}/LICENSES && \
    mkdir -p ${AZ_NHC_ROOT}/conf && \
    mkdir -p ${AZ_NHC_ROOT}/output && \
    mkdir -p ${AZ_NHC_ROOT}/default && \
    mkdir -p ${AZ_NHC_ROOT}/default/conf && \
    mkdir -p ${AZ_NHC_ROOT}/topofiles && \
    mkdir -p ${AZ_NHC_ROOT}/lib

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

# Copy necessary files
COPY LICENSE ${AZ_NHC_ROOT}/LICENSES/azure-nhc_LICENSE.txt
COPY README.md ${AZ_NHC_ROOT}/README.md
COPY customTests/*.nhc /etc/nhc/scripts/
COPY conf ${AZ_NHC_ROOT}/default/conf

# Install OFED
RUN cd /tmp && \
    wget -q https://content.mellanox.com/ofed/MLNX_OFED-${OFED_VERSION}/MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64.tgz && \
    tar xzf MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64.tgz && \
    MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu22.04-x86_64/mlnxofedinstall --user-space-only --without-fw-update --without-ucx-cuda --force --all && \
    rm -rf /tmp/MLNX_OFED_LINUX*

# Install OpenMPI
RUN cd /tmp && \ 
    wget -q "https://download.open-mpi.org/release/open-mpi/v4.1/openmpi-${OPEN_MPI_VERSION}.tar.gz" && \
    tar -xvf openmpi-${OPEN_MPI_VERSION}.tar.gz && \
    cd openmpi-${OPEN_MPI_VERSION} && \
    cp LICENSE ${AZ_NHC_ROOT}/LICENSES/OpenMPI_LICENSE.txt && \
    ./configure --prefix=/opt/openmpi --enable-mpirun-prefix-by-default --with-platform=contrib/platform/mellanox/optimized && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/openmpi-${OPEN_MPI_VERSION} openmpi-${OPEN_MPI_VERSION}.tar.gz

# Install Perf-Test
RUN  mkdir -p /tmp/perftest && \
    cd /tmp/perftest && \
    archive_url=https://github.com/linux-rdma/perftest/releases/download/${PERF_TEST_VERSION}/perftest-${PERF_TEST_VERSION}.${PERF_TEST_HASH}.tar.gz && \
    wget -q -O - $archive_url | tar -xz --strip=1 -C  /tmp/perftest && \
    ./configure && \
    make -j$(nproc) && \
    cp ib_write_bw ${AZ_NHC_ROOT}/bin/ib_write_bw_nongdr && \
    cp COPYING ${AZ_NHC_ROOT}/LICENSES/perftest_LICENSE && \
    rm -rf /tmp/perftest

# Install RCCL
RUN mkdir -p /opt/rccl &&\
    git clone https://github.com/ROCm/rccl.git --depth 1 /tmp/rccl &&\
    cd /tmp/rccl &&\
    mkdir build &&\
    cd build &&\
    CXX=/opt/rocm/bin/hipcc cmake -DCMAKE_PREFIX_PATH=/opt/rocm/ -DCMAKE_INSTALL_PREFIX=/opt/rccl .. &&\
    make -j$(nproc) &&\
    make install &&\
    sysctl kernel.numa_balancing=0 &&\
    echo "kernel.numa_balancing=0" | sudo tee -a /etc/sysctl.conf &&\
    rm -rf /tmp/rccl

# Install RCCL-Tests
RUN git clone https://github.com/ROCm/rccl-tests.git  --depth 1 /tmp/rccl-tests && \
    cd /tmp/rccl-tests &&\
    echo "gfx942" > target.lst && \
    echo "gfx90a" >> target.lst && \
    mkdir -p /opt/rccl-tests &&\
    ROCM_TARGET_LST=$(pwd)/target.lst make MPI=1 NCCL_HOME=/opt/rccl CUSTOM_RCCL_LIB=/opt/rccl/lib/librccl.so BUILDDIR=/opt/rccl-tests  &&\
    rm -rf /tmp/rccl-tests
#DOCKER_RUN_ARGS="--name=testnhc --net=host -v /sys:/hostsys/  --cap-add SYS_ADMIN --cap-add=CAP_SYS_NICE --privileged --device /dev/fdk --device /dev/dri --security-opt seccomp=unconfined "

# Copy entrypoint script
COPY dockerfile/aznhc-entrypoint.sh ${AZ_NHC_ROOT}
RUN chmod +x ${AZ_NHC_ROOT}/aznhc-entrypoint.sh
