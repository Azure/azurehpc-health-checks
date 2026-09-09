# aarch64 (Grace/Blackwell) variant of azure-nvrt-nhc.dockerfile.

################################################################################
# STAGE 1: Builder — compile all tools using the full CUDA devel image
################################################################################
FROM nvcr.io/nvidia/cuda:13.0.0-cudnn-devel-ubuntu24.04 AS builder

SHELL ["/bin/bash", "-c"]

# Semicolon-separated list of supported GPU compute capabilities, shared by
# nccl-tests' NVCC_GENCODE and nvbandwidth's CMAKE_CUDA_ARCHITECTURES.
# 90 = H100/H200 (compat), 100 = B200/GB200, 103 = GB300.
ARG CUDA_ARCH_LIST="90;100;103"

ENV DOCA_VERSION=3.3.0
ENV NHC_VERSION=1.4.3
ENV NV_BANDWIDTH_VERSION=0.10.0
ENV OPEN_MPI_VERSION=5.0.5
ENV NCCL_TEST_VERSION=2.13.8

ENV AZ_NHC_ROOT="/azure-nhc"
ENV MPI_HOME=/opt/openmpi

WORKDIR /tmp

RUN apt-get update -y && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends          \
    git wget curl ca-certificates gnupg                 \
    cmake build-essential                               \
    libpci-dev libboost-program-options-dev             \
    libssl-dev devscripts bats                          \
    && rm -rf /var/lib/apt/lists/*

# Add the DOCA-Host public apt repo. Provides rdma-core/perftest/ucx at
# versions matching Azure's Grace host images.
RUN wget -qO - https://linux.mellanox.com/public/repo/doca/GPG-KEY-Mellanox.pub | \
    gpg --dearmor -o /usr/share/keyrings/doca-mellanox.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/doca-mellanox.gpg] https://linux.mellanox.com/public/repo/doca/${DOCA_VERSION}/ubuntu24.04/arm64-sbsa/ ./" \
    > /etc/apt/sources.list.d/doca.list && \
    apt-get update -y

# Install IB user-space needed to compile OpenMPI/perftest with verbs support,
# plus the prebuilt perftest binary itself (has GDR/--use_cuda support already).
RUN DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    rdma-core ibverbs-providers libibverbs-dev librdmacm-dev libibumad-dev    \
    infiniband-diags perftest ucx                                             \
    && mkdir -p ${AZ_NHC_ROOT}/bin ${AZ_NHC_ROOT}/LICENSES                    \
    && cp "$(command -v ib_write_bw)" ${AZ_NHC_ROOT}/bin/ib_write_bw          \
    && cp "$(command -v ib_write_bw)" ${AZ_NHC_ROOT}/bin/ib_write_bw_nongdr   \
    && (dpkg -L perftest | grep -i copyright | head -1 | xargs -I{} cp {} ${AZ_NHC_ROOT}/LICENSES/perftest_LICENSE || true) \
    && rm -rf /var/lib/apt/lists/*

# Build OpenMPI with explicit --with-verbs/--with-rdmacm
# pointed at the DOCA-provided headers/libs installed above.
RUN cd /tmp && \
    wget -q "https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-${OPEN_MPI_VERSION}.tar.gz" && \
    tar -xf openmpi-${OPEN_MPI_VERSION}.tar.gz && \
    cd openmpi-${OPEN_MPI_VERSION} && \
    mkdir -p ${AZ_NHC_ROOT}/LICENSES && \
    cp LICENSE ${AZ_NHC_ROOT}/LICENSES/OpenMPI_LICENSE.txt && \
    ./configure --prefix=/opt/openmpi --enable-mpirun-prefix-by-default \
        --with-verbs --with-rdmacm && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/openmpi-${OPEN_MPI_VERSION}*

# Save the NCCL license (libnccl2/libnccl-dev come preinstalled in the
# cudnn-devel base image at a version matching CUDA 13.0 arm64)
RUN cp /usr/share/doc/libnccl2/copyright ${AZ_NHC_ROOT}/LICENSES/nccl_LICENSE.txt || true

# Build NCCL-Tests. nccl-tests' default NVCC_GENCODE targets legacy archs
# (compute_35/50/60/61/70/80) that CUDA 13's nvcc no longer accepts
# ("Unsupported gpu architecture 'compute_60'"); override it using
# CUDA_ARCH_LIST (see top of file) instead of hardcoding archs here.
RUN cd /tmp && \
    wget -q -O - https://github.com/NVIDIA/nccl-tests/archive/refs/tags/v${NCCL_TEST_VERSION}.tar.gz | tar -xz && \
    cd nccl-tests-${NCCL_TEST_VERSION} && \
    NVCC_GENCODE="" && \
    for arch in ${CUDA_ARCH_LIST//;/ }; do \
        NVCC_GENCODE="${NVCC_GENCODE} -gencode=arch=compute_${arch},code=sm_${arch}"; \
    done && \
    last_arch="${CUDA_ARCH_LIST##*;}" && \
    NVCC_GENCODE="${NVCC_GENCODE} -gencode=arch=compute_${last_arch},code=compute_${last_arch}" && \
    make MPI=1 MPI_HOME=${MPI_HOME} CUDA_HOME=/usr/local/cuda \
        NVCC_GENCODE="${NVCC_GENCODE}" && \
    mkdir -p /opt/nccl-tests/build && \
    cp -r build/* /opt/nccl-tests/build/ && \
    rm -rf /tmp/nccl-tests-${NCCL_TEST_VERSION}

# Build NHC
RUN cd /tmp && \
    wget -O nhc-${NHC_VERSION}.tar.xz https://github.com/mej/nhc/releases/download/${NHC_VERSION}/lbnl-nhc-${NHC_VERSION}.tar.xz && \
    tar -xf nhc-${NHC_VERSION}.tar.xz && \
    rm -f nhc-${NHC_VERSION}.tar.xz && \
    cd lbnl-nhc-${NHC_VERSION} && \
    ./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec && \
    make test && \
    make install && \
    mkdir -p ${AZ_NHC_ROOT} && \
    mv /tmp/lbnl-nhc-${NHC_VERSION}* ${AZ_NHC_ROOT}

# Build nvbandwidth for the configured CUDA architectures
RUN cd /tmp && \
    wget -q -O - https://github.com/NVIDIA/nvbandwidth/archive/refs/tags/v${NV_BANDWIDTH_VERSION}.tar.gz | tar -xz && \
    cd nvbandwidth-${NV_BANDWIDTH_VERSION} && \
    cmake -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES="${CUDA_ARCH_LIST}" . && \
    make && \
    cp nvbandwidth ${AZ_NHC_ROOT}/bin/ && \
    cp LICENSE ${AZ_NHC_ROOT}/LICENSES/nvbandwidth_LICENSE && \
    rm -rf /tmp/nvbandwidth-${NV_BANDWIDTH_VERSION}

# Get Topofiles from AI/HPC images
RUN mkdir -p ${AZ_NHC_ROOT}/topofiles && \
    git clone --depth=1 https://github.com/Azure/azhpc-images.git /tmp/azhpc-images && \
    cp /tmp/azhpc-images/topology/* ${AZ_NHC_ROOT}/topofiles && \
    rm -rf /tmp/azhpc-images


################################################################################
# STAGE 2: Runtime — slim image with only what's needed to run health checks
################################################################################
FROM nvcr.io/nvidia/cuda:13.0.0-runtime-ubuntu24.04

LABEL maintainer="azurehpc-health-checks"

SHELL ["/bin/bash", "-c"]

ENV DOCA_VERSION=3.3.0

ENV AZ_NHC_ROOT="/azure-nhc"
ENV MPI_BIN=/opt/openmpi/bin
ENV MPI_INCLUDE=/opt/openmpi/include
ENV MPI_LIB=/opt/openmpi/lib
ENV MPI_MAN=/opt/openmpi/share/man
ENV MPI_HOME=/opt/openmpi
ENV PATH="${MPI_BIN}:${PATH}"

WORKDIR ${AZ_NHC_ROOT}

# Install runtime-only system packages
RUN apt-get update -y && DEBIAN_FRONTEND=noninteractive \
    apt-get install -y --no-install-recommends          \
    --allow-change-held-packages                        \
    numactl curl sudo systemd wget perl gnupg           \
    libgomp1 libcap2-bin hwloc                          \
    openssh-client net-tools bc                         \
    pciutils                                            \
    libnccl2                                            \
    bats                                                \
    && apt-get upgrade -y --allow-change-held-packages  \
    && rm -rf /var/lib/apt/lists/*

# Install IB user-space runtime libraries from the DOCA-Host public apt repo
RUN wget -qO - https://linux.mellanox.com/public/repo/doca/GPG-KEY-Mellanox.pub | \
    gpg --dearmor -o /usr/share/keyrings/doca-mellanox.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/doca-mellanox.gpg] https://linux.mellanox.com/public/repo/doca/${DOCA_VERSION}/ubuntu24.04/arm64-sbsa/ ./" \
    > /etc/apt/sources.list.d/doca.list && \
    apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    rdma-core ibverbs-providers libibverbs1 librdmacm1 libibumad3 infiniband-diags ucx \
    && rm -rf /var/lib/apt/lists/*

# Copy compiled artifacts from builder
COPY --from=builder /opt/openmpi          /opt/openmpi
COPY --from=builder /opt/nccl-tests       /opt/nccl-tests
COPY --from=builder /azure-nhc            /azure-nhc
COPY --from=builder /usr/sbin/nhc         /usr/sbin/nhc
COPY --from=builder /usr/sbin/nhc-genconf /usr/sbin/nhc-genconf
COPY --from=builder /usr/sbin/nhc-wrapper /usr/sbin/nhc-wrapper
COPY --from=builder /etc/nhc              /etc/nhc
COPY --from=builder /usr/libexec/nhc      /usr/libexec/nhc

# Register copied libs with ldconfig
RUN printf "/opt/openmpi/lib\n/azure-nhc/lib\n" > /etc/ld.so.conf.d/openmpi.conf && ldconfig

# Create workspace directories
RUN mkdir -p ${AZ_NHC_ROOT}/conf   \
             ${AZ_NHC_ROOT}/output

# Copy host context files (custom tests, configs, entrypoint)
COPY LICENSE ${AZ_NHC_ROOT}/LICENSES/azure-nhc_LICENSE.txt
COPY README.md ${AZ_NHC_ROOT}/README.md
COPY customTests/*.nhc /etc/nhc/scripts/
COPY conf ${AZ_NHC_ROOT}/default/conf
COPY dockerfile/aznhc-entrypoint.sh ${AZ_NHC_ROOT}
RUN chmod +x ${AZ_NHC_ROOT}/aznhc-entrypoint.sh
