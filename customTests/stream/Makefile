#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.




CFLAGS= -Ofast -mcmodel=large -ffp-contract=fast -lomp -fopenmp -fnt-store=aggressive -DNTIMES=20
OTHER_FLAGS= -mavx512vl -mavx512bf16 -mavx512vbmi -mavx512vbmi2 -mavx512vnni -mavx512bitalg -mavx512vpopcntdq 
ZEN4FLAGS= -mavx512f -DSTREAM_ARRAY_SIZE=2400000000 -march=znver4
ZEN4FLAGS= -DSTREAM_ARRAY_SIZE=2400000000 -march=znver4 
ZEN3FLAGS= -mavx2 -DSTREAM_ARRAY_SIZE=400000000 -march=znver3
ZEN2FLAGS= -mavx2 -DSTREAM_ARRAY_SIZE=400000000 -march=znver2

ZEN_OUTPUT= $(EXEC_DIR)/stream.exe
all: ZEN4

ZEN4:
	@echo $(CC)
	$(CC) $(CFLAGS) $(OTHER_FLAGS) $(ZEN4FLAGS)  stream.c -o $(ZEN_OUTPUT)

ZEN3:
	@echo $(CC)
	$(CC) $(CFLAGS) $(ZEN3FLAGS)  stream.c -o $(ZEN_OUTPUT)

ZEN2:
	@echo $(CC)
	$(CC) $(CFLAGS) $(ZEN3FLAGS)  stream.c -o $(ZEN_OUTPUT)

clean:
	rm $(ZEN4_OUTPUT)
