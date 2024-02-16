# Unit Test Scripts #

The [run_tests script](./unit-tests/run_tests.sh) can be used to run unit tests. The unit test use [Bash Automated Testing System](https://github.com/bats-core/bats-core) or bats for short.

The run script will attempt to install bats if it is not found.

## Usage ##

- ```./unit-tests/run_tests.sh```

## Expected output ##

The output should be similar to the snippet below.

``` bash
NHC_DIR not set. Using default: /home/rafsalas/azurehpc-health-checks
 ✓ Docker image pull check 
 ✓ Docker image ls check 
 ✓ Default checks Pass (Happy Path) 
 ✓ Checks adjusted to fail (Sad Path) 

4 tests, 0 failures
```
