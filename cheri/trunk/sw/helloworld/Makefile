#-
# Copyright (c) 2010 Gregory A. Chadwick
# Copyright (c) 2010-2013 Jonathan Woodruff
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2011 Steven J. Murdoch
# Copyright (c) 2011 Robert M. Norton
# Copyright (c) 2011 Wojciech A. Koszek
# Copyright (c) 2012-2013 Alan Mujumdar
# Copyright (c) 2013 A. Theodore Markettos
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
# BERI Makefile
#
# Makefile for simple BERI test image.
#
# 


CHERILIBS_DIR   = ../../../../cherilibs/trunk
TOOLS_DIR       = $(CHERILIBS_DIR)/tools
INCLUDE_DIR     = $(CHERILIBS_DIR)/include
BAREMETAL_DIR	= ../baremetal-lib

CC = mips-linux-gnu-gcc
AS = mips64-as
LD = mips-linux-gnu-ld
OBJCOPY = mips-linux-gnu-objcopy
OBJDUMP = mips64-objdump

ENDIANNESS = -EB
ifndef OPT
  OPT = -O2
endif
CFLAGS += $(ENDIANNESS) -march=mips64 -mabi=64 -G 0 -ggdb $(OPT) -I$(INCLUDE_DIR) -isystem $(MINILIB_DIR)/include -S
ASFLAGS = $(ENDIANNESS) -march=mips64 -mabi=64 -G 0 -ggdb $(OPT)

c_objects := test.o $(BAREMETAL_DIR)/cheri-io.o $(BAREMETAL_DIR)/cheri-exp.o
as_objects := test.o $(BAREMETAL_DIR)/cheri-io.o $(BAREMETAL_DIR)/init.o $(BAREMETAL_DIR)/cheri-exp.o $(BAREMETAL_DIR)/lib.o

LDFLAGS = $(ENDIANNESS) -G 0 -L$(BAREMETAL_DIR) -Tprog_link.ld -m elf64btsmip

HEX_FILES =			\
	mem64.hex

TARGETS=			\
	binary.dump	\
	elf.dump

MEMCONV=python $(TOOLS_DIR)/memConv.py

../../mem64.hex: $(c_objects) $(as_objects)
	$(LD) $(LDFLAGS) $(as_objects) -o mem.elf
	$(OBJCOPY) -S -O binary mem.elf mem.bin
	$(OBJDUMP) -xsSd mem.elf > bsim-elf.dump
	$(MEMCONV)
	cp mem64.hex ../../

print-versions:
	$(LD) --version | head -n1
	$(OBJCOPY) --version | head -n1
	$(CC) --version | head -n1
	$(AS) --version | head -n1
	python -V | head -n1

test.o: test.c comlib.c
	$(CC) -Wall -Werror -Wno-return-type -c -o test.s test.c $(CFLAGS)
	$(AS) -o test.o test.s $(ASFLAGS)
lib.o: lib.s
	$(AS) -o $(BAREMETAL_DIR)/lib.o $(BAREMETAL_DIR)/lib.s $(ASFLAGS)
test.c: $(INCLUDE_DIR)/parameters.h

.SUFFIXES:
#.SUFFIXES: .o .c .s

%.s: %.c
	echo $^
	$(CC) $(CFLAGS) -o $@ $^
%.o: %.s
	$(AS) $(ASFLAGS) -o $@ $^

clean:
	rm -f *.elf
	rm -f *.bin
	rm -f *.o $(as_objects)
	rm -f test.s
	rm -f $(HEX_FILES)
	rm -f $(BSIM_TARGETS)
	rm -f $(VERILOG_TARGETS)
