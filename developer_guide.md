# Az NHC Developer Guide #

## Pre-requisites  ##

  - Running on a VM which has the environment in which you would like AzNHC to run in.
  - Install AzNHC

## Creating a custom NHC configure file for your environment ##

1. You have two choices when creating a conf file.
   - You can generate a conf file using nhc-gen (Recommended). The following steps cover this scenario.
   - You can write one from scratch. Look at existing conf files for reference.
2. Run the following command to generate a custom conf file for the host
    - Run: ```sudo nhc-genconf -c <conf name>.conf```
    - Adjust file ownership: ```sudo chown $USER:$USER nd.conf```
3. Modify the conf file to generalize it for any host.
    - Remove the following sections:
        - "Filesystem checks" (You may choose to leave. However, you must ensure this generalizes well across your VMs)
        - "DMI Checks"
        - "Process checks"
        Note: essentially we are just leaving the "Hardware checks"
    - Generalize the the file to run on any host by replacing the " hostname ||" in front of each test with " * ||". The wild card symbol is used to specify any host.
        -```sed -i "s/$(hostname)/*/" <conf name>.conf```
4. Add applicable custom tests:
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
    - Note: Reference other conf files for formatting guidance.
    - Note: You may choose to write a custom test and add it. Please reference NHC documentation on how to do this.
5. Test the new conf file
    - ```sudo ./run-health-checks.sh -c <conf name>.conf```

## Steps for adding a new SKU ##

1. Follow steps in "Creating a custom NHC configure file" section to generate a configure file. 
    - Name the conf file after the SKU name. i.e. for Standard_ND40rs_v2 the conf file would be nd40rs_v2.conf
    - You can use these commands to get the proper naming convention:
      - ```SKU=$( curl -H Metadata:true --max-time 10 -s "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2021-01-01&format=text" | sed 's/Standard_//')```
      - ```SKU="${SKU,,}"; echo $SKU```

2. Once the file is generated you can add applicable custom tests.
    - It may be necessary to check if the custom test supports the given SKU. Take a look at the specific custom test in the customTests directory.
    - Make any changes necessary to the custom test. You may want to run it as a normal bash script to test it works and check expected values.
    - Once tested add the specific expected values and arguments to the the conf file for that test. Refer to existing conf files for guidance.

3. Once all tests have been added to the conf file, place the conf file in the conf file directory.

4. If the sku has accelerated network, modify the run [run-health-checks.sh](run-health-checks.sh)  
    - Locate the two lists AN40 (Accelerated network rate 40 GBS) and AN100 (Accelerated network rate 100 GBS)
cd
    ![Alt text](image.png)
    - Add the SKU name to this list

5. Remove any accerelated network checks from the conf file as the run script will add these on the fly.
    - delete " * || check_hw_ib rate  mlx5_an0:1"
    - delete " * || check_hw_eth eth1 "

5. Run the install script to add your new changes to AzNHC.

6. Test AzNHC by running ```sudo ./run-health-checks.sh -c <conf name>.conf```
