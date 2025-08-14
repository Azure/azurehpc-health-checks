# Tests Scripts #

| Test Suite      | Script Command      |
| ------------- | ------------- |
| Integration Tests | [./unit-tests/run_tests.sh](./unit-tests/run_tests.sh) |
| Unit Tests | [./unit-tests/run_tests_agnostic.sh](./unit-tests/run_tests_agnostic.sh) |

The unit test use [Bash Automated Testing System](https://github.com/bats-core/bats-core) or bats for short.

The [run_tests script](./unit-tests/run_tests.sh) can be used to run integration tests. These are expected to run on HPC hardware. The run_tests script will attempt to install bats if it is not found.

The [run_tests_agnostic script](./unit-tests/run_tests_agnostic.sh) doesn't require HPC hardware.

## Usage ##

- ```./unit-tests/run_tests.sh $NHC_PATH_OPTIONAL```
- ```./unit-tests/run_tests_agnostic.sh -d $NHC_PATH_OPTIONAL``` 

## Expected output ##

The output should be similar to the snippet below.

``` bash
NHC_DIR not set. Using default: /home/rafsalas/azurehpc-health-checks
 ✓ Default checks Pass (Happy Path) 
 ✓ Checks adjusted to fail (Sad Path) 

2 tests, 0 failures
```
