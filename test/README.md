# Unit Test Scripts #

The [run_tests script](./unit-tests/run_tests.sh) can be used to run unit tests. It requires the name of the function/test to be performed as an argument. It will run the test and report a Passed/Failed result.

## Usage ##

- ```./unit-tests/run_tests.sh < test > ```
- test choices: happy_path, sad_path

## Expected output ##

The output indicates what test is running and the status of that test.

``` bash
Running  happy_path test
happy_path test: Passed
```
