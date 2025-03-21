# Az NHC Developer Guide #

Az NHC is ran inside an Ubuntu 22.04 docker container. See instructions for how to address changes in the docker image.

## Pre-requisites ##

- Running on the target VM SKU
- Docker installed
- Cloned AZ NHC repo

## Docker image Considerations ##

1. The [run script](./run-health-checks.sh) will copy any new conf files as well as any new customTests found in their respective directories.
    This means that the docker image does not have to be rebuilt during development unless the following conditions apply:
    - Adding a new binary
    - Adding a new ENV variable (consider passing in the variable in the run script)
    - Changes to the directory structure in the docker workspace (should not happen very often)

    Any changes to how the ```docker run``` command is ran needs to be updated in [Docker docs](./dockerfile/README.MD) and any additional instructions in the main [docs](./README.md).

2. Launching the docker container as an interactive session may be easier to develop on:

  ```bash
    NVIDIA_RT="--runtime=nvidia" # only for GPU SKUs, Omit for non-gpu
    DOCK_IMG_NAME=mcr.microsoft.com/aznhc/aznhc-nv
    OUTPUT_PATH=${AZ_NHC_ROOT}/output/aznhc.log
    kernel_log=/var/log/syslog

    DOCKER_RUN_ARGS="--name=aznhc --net=host --rm ${NVIDIA_RT} --cap-add SYS_ADMIN --cap-add=CAP_SYS_NICE --privileged \
        -v /sys:/hostsys/ \
        -v $OUTPUT_PATH:$WORKING_DIR/output/aznhc.log \
        -v ${kernel_log}:$WORKING_DIR/syslog
        -v ${AZ_NHC_ROOT}/customTests:$WORKING_DIR/customTests"
    sudo docker run -itd ${DOCKER_RUN_ARGS}  "${DOCK_IMG_NAME}" bash
    sudo docker exec -it aznhc bash
  ```

  Note: ensure to stop the container once finished
3. The [entry point script](./dockerfile/aznhc-entrypoint.sh) is the script inside the docker conatiner that launches NHC. You can reference it for how to launch NHC manually in the container.

## Creating a custom NHC configure file ##

1. When writing the conf files reference the existing conf files as a template.
2. Add applicable custom tests:
    - GPU SKUs
      - check_gpu_count
      - check_nvsmi_healthmon
      - check_gpu_xid
      - check_cuda_bw
      - check_gpu_ecc
      - check_gpu_clock_throttling
      - check_nccl_allreduce
    - CPU SKU
      - check_cpu_stream
    - IB enabled SKU
      - check_ib_bw_gdr (GDR enabled)
      - check_ib_bw_non_gdr
      - check_ib_link_flapping
    - Notes
      - Reference other conf files for formatting guidance.
      - You may choose to write a custom test and add it. Please reference NHC documentation on how to do this.
      - It may be necessary to check if the custom test supports the given SKU. Look at the specific custom test in the customTests directory.
      - You may want to run the test as a normal bash script to verify it works and check expected values.

3. Test the new conf file
    - Use [docker pull script](./dockerfile/pull-image-mcr.sh) to pull down the latest image: ```sudo ./pull-image-mcr.sh```
    - ```sudo ./run-health-checks.sh -c <conf name>.conf```
    - This will launch the docker container and add the conf file to the container.

4. Complete [Final Step](#final-step-building-the-docker-image) section for building the new Docker image.

## Steps for adding a new SKU ##

1. Follow steps in "Creating a custom NHC configure file" section to generate a configure file.
    - Name the conf file after the SKU name. i.e. for Standard_ND40rs_v2 the conf file would be nd40rs_v2.conf
    - You can use these commands to get the proper naming convention:
      - ```SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text" | tr '[:upper:]' '[:lower:]' | sed 's/standard_//')```
      - ```echo $SKU```

2. Once the conf file has been created and applicable custom tests have been added, place the conf file in the 'conf' directory.

3. If the sku has accelerated network, modify the run [run-health-checks.sh](run-health-checks.sh)  
    - Locate the two lists AN40 (Accelerated network rate 40 GBS) and AN100 (Accelerated network rate 100 GBS)
    - Add the SKU name to this list

4. Remove any accelerated network checks from the conf file as the run script will add these on the fly.
    - delete " * || check_hw_ib rate  mlx5_an0:1"
    - delete " * || check_hw_eth eth1 "

5. Run the install script to add your new changes to AzNHC.

6. Test Az NHC, see ["Creating a custom NHC configure file"](#creating-a-custom-nhc-configure-file) section step 3

7. Complete [Final Step](#final-step-building-the-docker-image) section for building the new Docker image.

## Final Step: Building the Docker Image ##

These manual build steps are necessary while automation is being developed to perform the image build.

1. The docker image must be built on A GPU enabled SKU, even if the target SKU is CPU based.
2. To build us the following command: ```sudo dockerfile/build_image cuda```
3. Once you have verified you docker image build, reach out to the repo owners to have them test and push the image to the container registry.
