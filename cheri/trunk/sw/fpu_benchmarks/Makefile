#-
# Copyright (c) 2012 Robert N. M. Watson
# Copyright (c) 2012-2013 Jonathan Woodruff
# Copyright (c) 2013 Bjoern A. Zeeb
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for
# additional information regarding copyright ownership.  BERI licenses this
# file to you under the BERI Hardware-Software License, Version 1.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at:
#
#   http://www.beri-open-systems.org/legal/license-1-0.txt
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
# @BERI_LICENSE_HEADER_END@
#

#
# Build environment for miniboot.
#

CHERIROOT?=../..
CHERIROOT_ABS:=$(realpath $(CHERIROOT))
CHERILIBS?=../../../../cherilibs/trunk
CHERILIBS_ABS:=$(realpath $(CHERILIBS))
CHERICONF?=simconfig
TOOLS_DIR=${CHERILIBS_ABS}/tools
TOOLS_DIR_ABS:=$(realpath $(TOOLS_DIR))

MEMCONV=python $(TOOLS_DIR_ABS)/memConv.py
AS=mips64-as
CC=clang
SIM_CC=clang

CFLAGS += -fno-honor-nans -Wall -Wextra -O2 -std=gnu99 -funroll-loops -D OUTPUT_IMAGE
#CFLAGS += -fno-honor-nans -Wall -Wextra -std=gnu99 -D OUTPUT_IMAGE
INTELFLAGS = -march=corei7
MIPSFLAGS = -fno-pic -target mips64-unknown-linux -integrated-as -D MIPS

LDSCRIPT=test_cached.ld

BENCHMARK_C_FILES = write.c mipsmath.c std.c \
					data_scalar.c project_scalar.c mandelbrot_scalar.c \
					data_vectorised.c project_vectorised.c mandelbrot_vectorised.c \
					init.c 

OBJECTS = miniboot.o write.o mipsmath.o std.o \
		  data_scalar.o project_scalar.o mandelbrot_scalar.o \
		  data_vectorised.o project_vectorised.o mandelbrot_vectorised.o \
		  init.o exceptionhandler.o lib.o

.DUMMY=all
all: miniboot.elf mem.bin miniboot.dump

.PHONY: copy
copy : all
	cp initial.hex ~/ctsrd/cheri/trunk/boards/terasic_de4/

%.o : %.s
	$(AS) -EB -march=mips64 -mabi=64 -G0 -ggdb -o $@ $<
%.o : %.c
	$(CC) -c $(MIPSFLAGS) $(CFLAGS) -o $@ $< 
miniboot.elf : $(OBJECTS) $(LDSCRIPT)
	mips-linux-gnu-ld -lm -EB -G0 -T$(LDSCRIPT) $(OBJECTS) -o $@ -m elf64btsmip 
miniboot.mem : miniboot.elf
	mips-linux-gnu-objcopy -S -O binary $< $@
miniboot.dump : miniboot.elf
	mips64-objdump -xsSD $< > $@

mem.bin: miniboot.mem
	cp $< $@
	$(MEMCONV) bsim
	$(MEMCONV) verilog

run: all
	LD_LIBRARY_PATH=$(CHERILIBS_ABS)/peripherals			\
	    CHERI_KERNEL=kernel						\
	    CHERI_CONFIG=$(CHERICONF)					\
	    ${CHERIROOT_ABS}/sim

trace: all
ifndef CHERI_TRACE_LOG
	@echo "Must set CHERI_TRACE_LOG to use trace target"
	@exit 1
endif
ifndef CHERI_CONSOLE_SOCKET
	@echo "Must set CHERI_CONSOLE_SOCKET to use trace target"
	@exit 1
endif
	LD_LIBRARY_PATH=$(CHERILIBS_ABS)/peripherals			\
	    CHERI_KERNEL=kernel						\
	    CHERI_CONSOLE_SOCKET=$(CHERI_CONSOLE_SOCKET)		\
	    CHERI_CONFIG=$(CHERICONF)					\
	    ${CHERIROOT_ABS}/sim		\
	    +regDump +trace +cTrace +instructionBasedCycleCounter > $(CHERI_TRACE_LOG)

gxemul:
	../../../cheritest/trunk/tools/gxemul/CTSRD-CHERI-gxemul-8d92b42/gxemul -V -E oldtestmips -M 3072 kernel.gxemul miniboot.elf

sim_benchmark: $(BENCHMARK_C_FILES) -lm -lrt
	$(SIM_CC) $^ -o $@ $(CFLAGS) $(INTELFLAGS)

data_to_png: write.c std.c data_to_png.c 
	$(SIM_CC) $^ -o $@ $(CFLAGS) $(INTELFLAGS) -L$(HOME)/libs/lib -lIL -lrt

.PHONY: run_benchmark
run_benchmark: sim_benchmark data_to_png
	rm -f mandelbrot_scalar.png project_scalar.png mandelbrot.png project.png
	./$< | ./run_benchmark.py 
	data_to_png mandelbrotscalar_data mandelbrot_scalar.png
	data_to_png projectscalar_data project_scalar.png
	data_to_png mandelbrot_data mandelbrot.png
	data_to_png project_data project.png
	rm mandelbrot_data project_data

.PHONY: clean_sim
clean_sim:
	rm -f mandelbrot.png project.png sim_benchmark

clean:
	rm -f *.o *.elf *.mem *.dump mem.bin mem?.hex initial.hex mem.hex mem64.hex sim.so kernel-sdroot
