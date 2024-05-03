# AzureHPC Node Health Check #

[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_apis/build/status%2Fhpc-vm-health-check-framework?branchName=master)](https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_build/latest?definitionId=29&branchName=master)

|OS Version|Status Badge|
|----------|------------|
|ND96asr v4|[![Build Status](https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_apis/build/status%2Fhpc-vm-health-check-framework?branchName=master&jobName=Run_Health_Checks)](https://dev.azure.com/hpc-platform-team/hpc-vm-health-check-framework/_build/latest?definitionId=29&branchName=master)

## Description ##

AzureHPC Node Health Checks provides an automated suite of test that targets specific Azure HPC offerings. This is an extension of [LBNL Node Health Checks](https://github.com/mej/nhc). 

## Supported SKU Offerings ##

- [NDm H100 v5-series](https://learn.microsoft.com/en-us/azure/virtual-machines/nd-h100-v5-series)
- [NCads H100 v5-series](https://learn.microsoft.com/en-us/azure/virtual-machines/ncads-h100-v5)
- [NDm A100 v4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/ndm-a100-v4-series)
- [ND A100 v4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/nda100-v4-series)
- [NC A100 v4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/nc-a100-v4-series)
- [HBv4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv4-series)
- [HX-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hx-series)
- [HBv3-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv3-series)
- [HBv2-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv2-series)
- [NDv2-serries](https://learn.microsoft.com/en-us/azure/virtual-machines/ndv2-series)
- [HC-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hc-series)
- [ND mi300x v5-series](https://techcommunity.microsoft.com/t5/azure-high-performance-computing/azure-previews-nd-mi300x-v5-optimized-for-demanding-ai-and-hpc/ba-p/4002519)

## Setup ##

Az NHC (Azure Health Checks) uses a docker container to run the health checks. This makes setup rather easy:

1. Pull the image down using [pull script](./dockerfile/pull-image-acr.sh): ```sudo ./dockerfile/pull-image-acr.sh```
2. Verify you have the image: ```sudo docker container ls```

## Configuration ##

This project comes with default VM SKU test configuration files that list the tests to be run. You can modify existing configuration files to suit your testing needs. For information on modifying or creating configuration files please reference:

- [Developer Guide](./developer_guide.md)
- [LBNL Node Health Checks documentation](https://github.com/mej/nhc).

## Usage ##

- Invoke health checks using a script that determines SKU and runs the configuration file according to SKU for you:
```sudo ./run-health-checks.sh [-h|--help] [-c|--config <path to an NHC .conf file>] [-o|--output <directory path to output all log files>] [-e|--append_conf < path to conf file to be appended >] [-a|--all_tests] [-v|--verbose]```

  - See help menu for more options:

    | Option        | Argument    | Description                                                                                                                                   |
    |---------------|-------------|-----------------------------------------------------------------------------------------------------------------------------------------------|
    | -h, --help    |             | Display this help                                                                                                                             |
    | -c, --config  | conf file   | Optional path to a custom NHC config file. If not specified the current VM SKU will be detected and the appropriate conf file will be used.   |
    | -o, --output  | log file    | Optional path to output the health check logs to. All directories in the path must exist. If not specified it will use output to ./health.log |
    | -t, --timeout | n seconds   | Optional timeout in seconds for each health check. If not specified it will default to 500 seconds.                                           |
    | -e, --append_conf | conf file   | Append a custom conf file to the conf file being used for the test. Useful if you have a set of common tests you want to add to the default conf files provided. |
    | -a, --all     |             | Run ALL checks; don't exit on first failure.                                                                                                  |
    | -v, --verbose |             | If set, enables verbose and debug outputs.                                                                                                    |

  - Adding more tests to the configuration files may require modifying the time flag (-t) to avoid timeout. For the default tests provided we recommend setting the time out to 500 seconds but this may vary from machine to machine.
  - For other methods on launching Az NHC see [Az NHC docker documentation](./dockerfile/README.MD)

### Example usage ###
  
  1. Default configuration: ```sudo ./run-health-checks.sh```
  1. Verbose output with timeout of 600 seconds: ```sudo ./run-health-checks.sh -v -t 600```
  1. Custom conf and log file: ```sudo ./run-health-checks.sh -c /path/to/myconf.cong -o /path/to/mylog.log```
  1. Append a conf file to default conf:  ```sudo ./run-health-checks.sh -e /path/to/confToAdd.conf```
  1. Append a conf file to custom conf:  ```sudo ./run-health-checks.sh -c /path/to/custom.conf -e /path/to/confToAdd.conf```

## Distributed NHC ##

AzureHPC Node Health Checks also comes bundled with a distributed version of NHC, which is designed to run on a cluster of machines and report back to a central location. This is useful for running health checks on a large cluster with dozens or hundreds of nodes.

See [Distributed NHC](./distributed_nhc/README.md) for more information.

## Health Checks ##

Many of the hardware checks are part of the default NHC project. If you would like to learn more about these check out the [Node Health Checks project](https://github.com/mej/nhc).

The following are Azure custom checks added to the existing NHC suite of tests:

| Check | Component Tested | nd96asr_v4 expected| nd96amsr_a100_v4 expected | nd96isr_h100_v5 expected | hx176rs expected | hb176rs_v4 expected |
|-----|-----|-----|-----|-----|-----|-----|
| check_gpu_count | GPU count | 8 | 8 | 8 | NA | NA |
| check_nvlink_status | NVlink | no inactive links | no inactive links  | no inactive links  | NA | NA |
| check_gpu_xid | GPU XID errors | not present | not present | not present | NA | NA |
| check_nvsmi_healthmon | Nvidia-smi GPU health check | pass | pass | pass | NA | NA |
| check_gpu_bandwidth | GPU DtH/HtD bandwidth | 23 GB/s | 23 GB/s | 52 GB/s | NA | NA |
| check_gpu_ecc | GPU Mem Errors (ECC) |  20000000 | 20000000 | 20000000 | NA | NA |
| check_gpu_clock_throttling | GPU Throttle codes assertion | not present | not present | not present | NA | NA |
| check_nccl_allreduce | GPU NVLink bandwidth | 228 GB/s | 228 GB/s | 460 GB/s | NA | NA |
| check_ib_bw_gdr | IB device (GDR) bandwidth | 180 GB/s | 180 GB/s | 380 GB/s | NA | NA |
| check_ib_bw_non_gdr | IB device (non GDR) bandwidth | NA | NA | NA | 390 GB/s | 390 GB/s |
| check_nccl_allreduce_ib_loopback | GPU/GPU Direct RDMA(GDR) + IB device bandwidth | 18 GB/s | 18 GB/s | NA | NA | NA |
| check_hw_topology | IB/GPU device topology/PCIE mapping | pass | pass | pass | NA | NA |
| check_ib_link_flapping | IB link flap occurrence  | not present | not present | not present | not present | not present |
| check_cpu_stream | CPU compute/memory bandwidth | NA | NA | NA | 665500 MB/s | 665500 MB/s |

Notes:

- The scripts for all tests can be found in the [custom test directory](./customTests/)
- Not all supported SKUs are listed in the above table

## Legacy Releases ##

Azure NHC has recently changed to using docker containerization to allow for broader use. Due to this some features and supported SKUs may only be available on legacy releases and the Legacy branch.

Releases tagged less than v0.3.0 are considered legacy.

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

### Developer Guide ###

See the [Dev guide](./developer_guide.md) if you're planning on contributing to this project.

## Copyright and Licensing ##

This project has several dependencies. Usage and distribution of this software must adhere to the [AZ NHC License](./LICENSE) as well as the dependency licenses.
Copyright/licenses for the software package dependencies can be found in directory ```/azure-nhc/LICENSE``` and software installation directories on the docker image.

## Trademarks ##

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
