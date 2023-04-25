# Copyright (c) Microsoft Corporation.
# Licensed under the MIT license.

CC= /opt/AMD/aocc-compiler-4.0.0/bin/clang
CFLAGS= -Ofast -mcmodel=large -mavx2 -ffp-contract=fast -lomp -fopenmp -fnt-store=aggressive -DNTIMES=10
ZEN4FLAGS= -DSTREAM_ARRAY_SIZE=800000000 -march=znver4 
ZEN4_OUTPUT= stream.exe

all: ZEN4

ZEN4:
	$(CC) $(CFLAGS) $(ZEN4FLAGS) stream.c -o $(ZEN4_OUTPUT)

clean:
	rm $(ZEN4_OUTPUT)
