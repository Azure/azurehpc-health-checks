# [EXPERIMENTAL] Ubuntu 26.04 HPC image for NVIDIA A100
#
# This is a best-effort experiment to support Ubuntu 26.04 for NVIDIA A100
# (NC/ND A100 v4-series) health checks.  Some components (e.g. MLNX OFED and
# Lustre) may not yet have Ubuntu 26.04 packages; those steps are skipped
# gracefully so the build does not crash.
#
# NVIDIA CUDA toolkit for Ubuntu 26.04:
#   https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/

FROM ubuntu:26.04

LABEL maintainer="azurehpc-health-checks"

SHELL ["/bin/bash", "-c"]

# OFED 24.10 is the first release that may ship ubuntu2604 packages.
# If the download fails we continue without InfiniBand user-space libraries.
ENV OFED_VERSION=24.10-1.1.4.0
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


# ── Base packages ─────────────────────────────────────────────────────────────
RUN apt-get update -y                                \
    && DEBIAN_FRONTEND=noninteractive                \
    apt-get install -y                               \
    --no-install-recommends                          \
    numactl                                          \
    git                                              \
    curl                                             \
    sudo                                             \
    systemd                                          \
    wget                                             \
    libgomp1                                         \
    libcap2-bin                                      \
    cmake                                            \
    libpci-dev                                       \
    hwloc                                            \
    build-essential                                  \
    libboost-program-options-dev                     \
    libssl-dev                                       \
    devscripts                                       \
    openssh-client                                   \
    net-tools                                        \
    bats                                             \
    bc                                               \
    gnupg
RUN apt-get upgrade -y

RUN mkdir -p ${AZ_NHC_ROOT}/LICENSES
COPY LICENSE ${AZ_NHC_ROOT}/LICENSES/azure-nhc_LICENSE.txt
COPY README.md ${AZ_NHC_ROOT}/README.md


# ── CUDA toolkit (from NVIDIA Ubuntu 26.04 repository) ────────────────────────
# Reference: https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/
RUN cd /tmp \
    && wget -q https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/cuda-keyring_1.1-1_all.deb \
    && dpkg -i cuda-keyring_1.1-1_all.deb \
    && rm cuda-keyring_1.1-1_all.deb \
    && apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       cuda-toolkit-12-4 \
       libcudnn9-cuda-12


# ── MLNX OFED (best-effort – Lustre excluded; skipped if no ubuntu2604 build) ─
# Lustre kernel client may not be available on Ubuntu 26.04 yet; use
# --without-lustre so the installer does not abort if those packages are absent.
RUN cd /tmp \
    && OFED_TGZ="MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu26.04-x86_64.tgz" \
    && OFED_URL="https://content.mellanox.com/ofed/MLNX_OFED-${OFED_VERSION}/${OFED_TGZ}" \
    && if wget -q "${OFED_URL}"; then \
           tar xzf "${OFED_TGZ}" \
           && "MLNX_OFED_LINUX-${OFED_VERSION}-ubuntu26.04-x86_64/mlnxofedinstall" \
                  --user-space-only \
                  --without-fw-update \
                  --without-ucx-cuda \
                  --without-lustre \
                  --force \
                  --all \
           && rm -rf /tmp/MLNX_OFED_LINUX*; \
       else \
           echo "WARNING: MLNX OFED ${OFED_VERSION} not yet available for Ubuntu 26.04 – skipping OFED installation"; \
       fi


# ── OpenMPI ───────────────────────────────────────────────────────────────────
# The Mellanox-optimised platform file requires a full OFED installation;
# fall back to a generic build when OFED is absent.
RUN cd /tmp \
    && wget -q "https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-${OPEN_MPI_VERSION}.tar.gz" \
    && tar -xvf openmpi-${OPEN_MPI_VERSION}.tar.gz \
    && cd openmpi-${OPEN_MPI_VERSION} \
    && cp LICENSE ${AZ_NHC_ROOT}/LICENSES/OpenMPI_LICENSE.txt \
    && if [ -d /usr/include/infiniband ]; then \
           ./configure --prefix=/opt/openmpi \
               --enable-mpirun-prefix-by-default \
               --with-platform=contrib/platform/mellanox/optimized; \
       else \
           ./configure --prefix=/opt/openmpi \
               --enable-mpirun-prefix-by-default; \
       fi \
    && make -j$(nproc) \
    && make install \
    && rm -rf /tmp/openmpi-${OPEN_MPI_VERSION} openmpi-${OPEN_MPI_VERSION}.tar.gz


# ── NCCL ──────────────────────────────────────────────────────────────────────
ARG host_nccl_dir=dockerfile/build_exe/nccl-${NCCL_VERSION}
RUN mkdir -p /opt/nccl
COPY ${host_nccl_dir} /opt/nccl
RUN cd /opt/nccl/build/pkg/deb/ \
    && dpkg -i libnccl2_${NCCL_VERSION}+cuda12.8_amd64.deb \
    && dpkg -i libnccl-dev_${NCCL_VERSION}+cuda12.8_amd64.deb \
    && cp /opt/nccl/LICENSE.txt ${AZ_NHC_ROOT}/LICENSES/nccl_LICENSE.txt \
    && rm -rf /opt/nccl


# ── NCCL-Tests ────────────────────────────────────────────────────────────────
ARG host_nccl_test_dir=dockerfile/build_exe/nccl-tests
COPY ${host_nccl_test_dir} /opt/nccl-tests


# ── NHC ───────────────────────────────────────────────────────────────────────
RUN cd /tmp \
    && wget -O nhc-${NHC_VERSION}.tar.xz \
           https://github.com/mej/nhc/releases/download/${NHC_VERSION}/lbnl-nhc-${NHC_VERSION}.tar.xz \
    && tar -xf nhc-${NHC_VERSION}.tar.xz \
    && rm -f nhc-${NHC_VERSION}.tar.xz \
    && cd lbnl-nhc-${NHC_VERSION} \
    && ./configure --prefix=/usr --sysconfdir=/etc --libexecdir=/usr/libexec \
    && make test \
    && make install \
    && mv /tmp/lbnl-nhc-${NHC_VERSION}* ${AZ_NHC_ROOT}


# ── Workspace directories ─────────────────────────────────────────────────────
RUN mkdir -p ${AZ_NHC_ROOT}/bin \
    && mkdir -p ${AZ_NHC_ROOT}/conf \
    && mkdir -p ${AZ_NHC_ROOT}/output \
    && mkdir -p ${AZ_NHC_ROOT}/default \
    && mkdir -p ${AZ_NHC_ROOT}/default/conf \
    && mkdir -p ${AZ_NHC_ROOT}/topofiles \
    && mkdir -p ${AZ_NHC_ROOT}/lib


# ── Config & topology files ───────────────────────────────────────────────────
COPY customTests/*.nhc /etc/nhc/scripts/
COPY conf ${AZ_NHC_ROOT}/default/conf

RUN git clone https://github.com/Azure/azhpc-images.git /tmp/azhpc-images \
    && cp /tmp/azhpc-images/topology/* ${AZ_NHC_ROOT}/topofiles \
    && rm -rf /tmp/azhpc-images


# ── AOCC / STREAM (best-effort – AOCC deb may not support Ubuntu 26.04) ───────
RUN cd /tmp \
    && if wget -q https://download.amd.com/developer/eula/aocc-compiler/aocc-compiler-${AOCC_VERSION}_amd64.deb; then \
           apt install -y ./aocc-compiler-${AOCC_VERSION}_amd64.deb \
           && rm aocc-compiler-${AOCC_VERSION}_amd64.deb; \
       else \
           echo "WARNING: AOCC ${AOCC_VERSION} not available – STREAM benchmark will be skipped"; \
       fi

COPY customTests/stream/Makefile /tmp/stream/
RUN if [ -f /opt/AMD/aocc-compiler-4.0.0/bin/clang ]; then \
        cd /tmp/stream \
        && wget https://www.cs.virginia.edu/stream/FTP/Code/stream.c \
        && make all CC=/opt/AMD/aocc-compiler-4.0.0/bin/clang EXEC_DIR=${AZ_NHC_ROOT}/bin \
        && rm -rf /tmp/stream \
        && cd ${AZ_NHC_ROOT}/LICENSES \
        && wget https://www.cs.virginia.edu/stream/FTP/Code/LICENSE.txt -O stream_LICENSE.txt; \
    else \
        echo "WARNING: AOCC clang not found – skipping STREAM build"; \
    fi

RUN if [ -f /opt/AMD/aocc-compiler-4.0.0/lib/libomp.so ]; then \
        cp /opt/AMD/aocc-compiler-4.0.0/lib/libomp.so ${AZ_NHC_ROOT}/lib; \
    fi

RUN if dpkg -l "aocc-compiler-4.0.0" 2>/dev/null | grep -q '^ii'; then \
        version=$(echo "$AOCC_VERSION" | sed 's/_1$//') \
        && apt remove aocc-compiler-"${version}" -y; \
    fi


# ── Perf-Test (GDR version, needs CUDA headers) ───────────────────────────────
RUN mkdir -p /tmp/perftest \
    && wget -q -O - \
       https://github.com/linux-rdma/perftest/releases/download/${PERF_TEST_VERSION}-0.29/perftest-${PERF_TEST_VERSION}-0.29.${PERF_TEST_HASH}.tar.gz \
       | tar -xz --strip=1 -C /tmp/perftest \
    && cd /tmp/perftest \
    && ./configure CUDA_H_PATH=/usr/local/cuda/include/cuda.h \
    && make -j$(nproc) \
    && cp ib_write_bw ${AZ_NHC_ROOT}/bin/ \
    && cp COPYING ${AZ_NHC_ROOT}/LICENSES/perftest_LICENSE \
    && rm -rf /tmp/perftest


# ── Perf-Test (non-GDR version) ───────────────────────────────────────────────
RUN mkdir -p /tmp/perftest_nongdr \
    && wget -q -O - \
       https://github.com/linux-rdma/perftest/releases/download/${PERF_TEST_VERSION}-0.29/perftest-${PERF_TEST_VERSION}-0.29.${PERF_TEST_HASH}.tar.gz \
       | tar -xz --strip=1 -C /tmp/perftest_nongdr \
    && cd /tmp/perftest_nongdr \
    && ./configure \
    && make -j$(nproc) \
    && cp ib_write_bw ${AZ_NHC_ROOT}/bin/ib_write_bw_nongdr \
    && rm -rf /tmp/perftest_nongdr


# ── NV Bandwidth tool ─────────────────────────────────────────────────────────
ARG host_nvbandwidth_dir=dockerfile/build_exe/nvbandwidth-${NV_BANDWIDTH_VERSION}
COPY ${host_nvbandwidth_dir}/nvbandwidth ${AZ_NHC_ROOT}/bin
COPY ${host_nvbandwidth_dir}/LICENSE ${AZ_NHC_ROOT}/LICENSES/nvbandwidth_LICENSE


# ── Entrypoint ────────────────────────────────────────────────────────────────
COPY dockerfile/aznhc-entrypoint.sh ${AZ_NHC_ROOT}
RUN chmod +x ${AZ_NHC_ROOT}/aznhc-entrypoint.sh
