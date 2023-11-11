#!/bin/bash

def test_calculate_sum():
    assert calculate_sum(2, 3) == 5
    assert calculate_sum(-2, 3) == 1
    assert calculate_sum(0, 0) == 0

test_calculate_sum