# AzureHPC Node Health Check #

[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_apis/build/status%2Fhpc-vm-health-check-framework?branchName=master)](https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_build/latest?definitionId=29&branchName=master)

|OS Version|Status Badge|
|----------|------------|
|ND96asr v4|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_apis/build/status%2Fhpc-vm-health-check-framework?branchName=master&jobName=Run_Health_Checks)](https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_build/latest?definitionId=29&branchName=master)

## Description ##

AzureHPC Node Health Checks provides an automated suite of test that targets specific Azure HPC offerings. This is an extension of [LBNL Node Health Checks](https://github.com/mej/nhc). 

## Supported Offerings ##

- [NDm H100 v5-series](https://learn.microsoft.com/en-us/azure/virtual-machines/nd-h100-v5-series)
- [NDm A100 v4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/ndm-a100-v4-series)
- [ND A100 v4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/nda100-v4-series)
- [NC A100 v4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/nc-a100-v4-series)
- [HBv4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv4-series)
- [HX-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hx-series)
- [HBv3-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv3-series)
- [HBv2-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv2-series)
- [NCv3-series](https://learn.microsoft.com/en-us/azure/virtual-machines/ncv3-series)


## Minimum Requirements ##

- Ubunutu 20.0, 22.04
- AlamaLinux >= 8.6

Note: Other distributions may work but are not supported.

## Setup ##

1. To install AzureHPC Node Health Checks run install script:
   ```sudo ./install-nhc.sh```

## Configuration ##

This project comes with default VM SKU test configuration files that list the tests to be run. You can modify existing configuration files to suit your tesing needs. For information on modifying or creating configuration files please reference [LBNL Node Health Checks documentation](https://github.com/mej/nhc).

## Usage ##

- Invoke health checks using a script that determines SKU and runs the configuration file according to SKU for you:
```sudo ./run-health-checks.sh [~/health.log]```
  - Default log file path is set to the current directory
  - See help menu for more options
- Invoke health checks directly:
```sudo nhc -c ./conf/"CONFNAME".conf -l ~/health.log -t 300```
  - To use a different log file location, specify the full path.
- Adding more tests to the configuration files may require modifying the time flag (-t) to avoid timeout. For the default tests provided we recommend setting the timing to 300 seconds but this may vary from machine to machine.

## Distributed NHC ##

AzureHPC Node Health Checks also comes bundled with a distributed version of NHC, which is designed to run on a cluster of machines and report back to a central location. This is useful for running health checks on a large cluster with dozens or hundreds of nodes.

See [Distributed NHC](./distributed-nhc/README.md) for more information.

## Health Checks ##

Many of the hardware checks are part of the default NHC project. If you would like to learn more about these check out the [Node Health Checks project](https://github.com/mej/nhc).

The following are Azure custom checks added to the existing NHC suite of tests:

| Check | Component Tested | nd96asr_v4 expected| nd96amsr_a100_v4 expected | nd96isr_h100_v5 expected | hx176rs expected | hb176rs_v4 expected |
|-----|-----|-----|-----|-----|-----|-----|
| check_gpu_count | GPU count | 8 | 8 | 8 | NA | NA |
| check_gpu_xid | GPU XID errors | not present | not present | not present | NA | NA |
| check_nvsmi_healthmon | Nvidia-smi GPU health check | pass | pass | pass | NA | NA |
| check_cuda_bw | GPU DtH/HtD bandwidth | 24 GB/s | 24 GB/s | 52 GB/s | NA | NA |
| check_gpu_ecc | GPU Mem Errors (ECC) |  20000000 | 20000000 | 20000000 | NA | NA |
| check_gpu_clock_throttling | GPU Throttle codes assertion | not present | not present | not present | NA | NA |
| check_nccl_allreduce | GPU NVLink bandwidth | 228 GB/s | 228 GB/s | 460 GB/s | NA | NA |
| check_ib_bw_gdr | IB device (GDR) bandwidth | 170 GB/s | 170 GB/s | 380 GB/s | NA | NA |
| check_ib_bw_non_gdr | IB device (non GDR) bandwidth | NA | NA | NA | 390 GB/s | 390 GB/s |
| check_nccl_allreduce_ib_loopback | GPU/GPU Direct RDMA(GDR) + IB device bandwidth | 18 GB/s | 18 GB/s | NA | NA | NA |
| check_hw_topology | IB/GPU device topology/PCIE mapping | pass | pass | pass | NA | NA |
| check_ib_link_flapping | IB link flap occurence | not present | not present | not present | not present | not present |
| check_cpu_stream | CPU compute/memory bandwidth | NA | NA | NA | 665500 MB/s | 665500 MB/s |

note: The scripts for all tests can be found in the [custom test directory](./customTests/)

note: not all supported SKUs are listed in the above table
## _References_ ##

- [LBNL Node Health Checks](https://github.com/mej/nhc)
- [Azure HPC Images](https://github.com/Azure/azhpc-images)

## Contributing ##

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks ##

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
