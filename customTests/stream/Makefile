#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.




CFLAGS= -Ofast -mcmodel=large -mavx2 -ffp-contract=fast -lomp -fopenmp -fnt-store=aggressive -DNTIMES=10
ZEN4FLAGS= -DSTREAM_ARRAY_SIZE=800000000 -march=znver4 
ZEN4_OUTPUT= $(EXEC_DIR)/stream.exe

all: ZEN4

ZEN4:
	@echo $(CC)
	$(CC) $(CFLAGS) $(ZEN4FLAGS) stream.c -o $(ZEN4_OUTPUT)

clean:
	rm $(ZEN4_OUTPUT)
