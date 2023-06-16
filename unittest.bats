#!usr/bin/env bats
@test "Test 1" {
    run bash -c "echo 'Hello World'"
    [ "$status" -eq 0 ]
    [ "$output" = "Hello World" ]
}

@test "addition using bc" {
  result="$(echo 2 + 2 | bc)"
  [ "$result" -eq 4 ]
}

# @test "can run our script" {
#     ./project.sh
# }