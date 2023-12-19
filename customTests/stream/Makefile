#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.




CFLAGS= -Ofast -mcmodel=large -ffp-contract=fast -lomp -fopenmp -fnt-store=aggressive -DNTIMES=20
OTHER_FLAGS= -mavx512vl -mavx512bf16 -mavx512vbmi -mavx512vbmi2 -mavx512vnni -mavx512bitalg -mavx512vpopcntdq 
ZEN4FLAGS= -mavx512f -DSTREAM_ARRAY_SIZE=400000000 -march=znver4
ZEN3FLAGS= -mavx2 -DSTREAM_ARRAY_SIZE=400000000 -march=znver3
ZEN2FLAGS= -mavx2 -DSTREAM_ARRAY_SIZE=400000000 -march=znver2

ZEN_OUTPUT2= $(EXEC_DIR)/stream2.exe
ZEN_OUTPUT3= $(EXEC_DIR)/stream3.exe
ZEN_OUTPUT4= $(EXEC_DIR)/stream4.exe

all: ZEN4 ZEN3 ZEN2

ZEN4:
	@echo $(CC)
	$(CC) $(CFLAGS) $(OTHER_FLAGS) $(ZEN4FLAGS)  stream.c -o $(ZEN_OUTPUT4)

ZEN3:
	@echo $(CC)
	$(CC) $(CFLAGS) $(ZEN3FLAGS)  stream.c -o $(ZEN_OUTPUT3)

ZEN2:
	@echo $(CC)
	$(CC) $(CFLAGS) $(ZEN2FLAGS)  stream.c -o $(ZEN_OUTPUT2)

clean:
	rm $(ZEN_OUTPUT4) $(ZEN_OUTPUT3) $(ZEN_OUTPUT2)
