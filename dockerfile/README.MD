# Az NHC Docker #

## OverView ##

Azure NHC is run within an Ubuntu 22.04 docker container with either Nvidia or AMD runtime enabled.

There are two ways of running Az NHC, with the provided run script and also as a stand alone container.

The container can be used on Nvidia or AMD GPU as well as CPU based SKUs. The [run script](../run-health-checks.sh) automaticly addresses the differences. If launching the container manually refer to the [Alternative Method Instructions](#alternative-method-instructions) section for guidance.

## Prerequisites ##

- Docker installed
- Sudo access to run the container

## Obtaining the Docker Image ##

The docker image is available publicly and can be pulled down the following ways:

- Using the [pull script](./pull-image-mcr.sh). ```sudo ./pull-image-mcr.sh cuda```
- Directly calling the the docker pull command: ```sudo docker pull mcr.microsoft.com/aznhc/aznhc-nv:latest``` or ```docker pull mcr.microsoft.com/aznhc/aznhc-rocm:latest```

Notes:

- To view the latest Nvidia/CUDA image current software versions take a look at the [CUDA Dockerfile](./azure-nvrt-nhc.dockerfile)
- To view the latest AMD/ROCm image current software versions take a look at the [ROCm Dockerfile](./azure-rocm-nhc.dockerfile)

## Run Modes ##

### Prefered Method: Run Script ###

The run script provides additional features that allow for customizations and extension of tests. See the [run script](../run-health-checks.sh) help menu for more details. This method is recommended above the others because it allows for dynamic customizations  of conf files and provides an output log file by default.

#### Prefered Method Instructions ####

These instructions will launch NHC with default settings. Additional customizations can be provided via arguments.

1. Clone the latest release of Az NHC (Azurehpc Health Checks)
2. Check if you have the docker image: ```sudo docker image ls```
3. If not, pull it down see [Obtaining the Docker Image](#obtaining-the-docker-image)
4. Now you can run NHC: ```sudo ./run-health-checks.sh```
5. Depending on the SKU, the default health checks can usually take up to 5 minutes to run. Time out is set to 500 seconds but can be changed via argument.
6. By default the output log path will be ```/path to current directory/health.log```. This can be changed via argument.

### Alternative Method: Manual Docker Launch ###

This method should be used when no customizations are needed. Care must be used to mount the syslog/message log or XID and IB Link flap tests will be skipped.

#### Alternative Method Instructions ####

1. Check if you have the docker image: ```sudo docker image ls```
2. If not, pull it down see [Obtaining the Docker Image](#obtaining-the-docker-image)
3. Locate your syslog or message log. Usually located in /var/log/ directory
4. See the following examples of how to launch manually:
   - With output and syslog provided:

   ```bash
    NVIDIA_RT="--runtime=nvidia" # only for GPU SKUs, Omit for non-gpu
    DOCK_IMG_NAME="mcr.microsoft.com/aznhc/aznhc-nv"
    OUTPUT_PATH=${AZ_NHC_ROOT}/output/aznhc.log
    kernel_log=/var/log/syslog

    DOCKER_RUN_ARGS="--name=aznhc --net=host --rm ${NVIDIA_RT} --cap-add SYS_ADMIN --cap-add=CAP_SYS_NICE --privileged --shm-size=8g\
        -v /sys:/hostsys/ \
        -v $OUTPUT_PATH:$WORKING_DIR/output/aznhc.log \
        -v ${kernel_log}:$WORKING_DIR/syslog
        -v ${AZ_NHC_ROOT}/customTests:$WORKING_DIR/customTests"
    sudo docker run ${DOCKER_RUN_ARGS}  "${DOCK_IMG_NAME}" bash -c "/azure-nhc/aznhc-entrypoint.sh"
   ```

   - With minimum mounted volumes:

   ```bash
    # This example would skip XID and IB link flap tests as the syslog is not mounted
    # This example also does not mount an output file. This means results will be printed to STDOUT.
    NVIDIA_RT="--runtime=nvidia" # only for GPU SKUs, omit for non-gpu
    DOCK_IMG_NAME="mcr.microsoft.com/aznhc/aznhc-nv"
    DOCKER_RUN_ARGS="--name=aznhc --net=host --rm ${NVIDIA_RT} --cap-add SYS_ADMIN --cap-add=CAP_SYS_NICE --privileged --shm-size=8g -v /sys:/hostsys/
    sudo docker run ${DOCKER_RUN_ARGS}  "${DOCK_IMG_NAME}" bash -c "/azure-nhc/aznhc-entrypoint.sh"
   ```
