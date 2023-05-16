AzureHPC Node Health Check
=====
Description
-----
AzureHPC Node Health Checks provides an automated suite of test that targets specific Azure HPC offerings. This is an extension of [LBNL Node Health Checks](https://github.com/mej/nhc). 

Supported Offerings
-----
- [NDm A100 v4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/ndm-a100-v4-series)
- [ND A100 v4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/nda100-v4-series)
- [HBv4-series](https://learn.microsoft.com/en-us/azure/virtual-machines/hbv4-series)

Minimum Requirements
-----
- Ubunutu 20.0, 22.04
- AlamaLinux >= 8.6

Setup
-----
1. To install AzureHPC Node Health Checks run install script:
   ```sudo ./install-nhc.sh```

Configuration
-------------
This project comes with default VM SKU test configuration files that list the tests to be run. You can modify existing configuration files to suit your tesing needs. For information on modifying or creating configuration files please reference [LBNL Node Health Checks documentation](https://github.com/mej/nhc).

Usage
-----
- Usage follows that of the LBNL NHC tests. i.e.:
```sudo nhc -l ~/healthlog.log -t 300 -c ~/ndv4.conf``` 
- Adding more tests to the configuration files may require modifying the time flag (-t) to avoid timeout. For the default tests provided we recommend setting the timing to 300 seconds but this may vary from machine to machine.

### _References_ ###
- [LBNL Node Health Checks](https://github.com/mej/nhc)
- [Azure HPC Images](https://github.com/Azure/azhpc-images)
## Contributing

This project welcomes contributions and suggestions.  Most contributions require you to agree to a
Contributor License Agreement (CLA) declaring that you have the right to, and actually do, grant us
the rights to use your contribution. For details, visit https://cla.opensource.microsoft.com.

When you submit a pull request, a CLA bot will automatically determine whether you need to provide
a CLA and decorate the PR appropriately (e.g., status check, comment). Simply follow the instructions
provided by the bot. You will only need to do this once across all repos using our CLA.

This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/).
For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or
contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.

## Trademarks

This project may contain trademarks or logos for projects, products, or services. Authorized use of Microsoft 
trademarks or logos is subject to and must follow 
[Microsoft's Trademark & Brand Guidelines](https://www.microsoft.com/en-us/legal/intellectualproperty/trademarks/usage/general).
Use of Microsoft trademarks or logos in modified versions of this project must not cause confusion or imply Microsoft sponsorship.
Any use of third-party trademarks or logos are subject to those third-party's policies.
