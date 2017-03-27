#-
# Copyright (c) 2014 Alexandre Joannou
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C (BERI) under one or more contributor
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

LIB_DIR = libs
OBJ_DIR = obj
OUT_DIR = output

CC = mips-linux-gnu-gcc
AS = mips64-as
LD = mips-linux-gnu-ld
OBJCOPY = mips-linux-gnu-objcopy
OBJDUMP = mips64-objdump
MEMCONV = python ../../../../../cherilibs/trunk/tools/memConv.py
OPT = -O2

CHERILIBS_DIR = ../../../../cherilibs/trunk

TESTS = scatter_gather shared_array parallel_sort merge_sort

.PHONY : clean mrproper mem64.hex

mem64.hex : $(OBJ_DIR)/init.o $(OBJ_DIR)/main.o $(addprefix $(OBJ_DIR)/,$(addsuffix .o,$(basename $(notdir $(wildcard $(LIB_DIR)/*.c))))) $(addprefix $(OBJ_DIR)/,$(addsuffix .o,$(TESTS)))
	mkdir -p $(OUT_DIR)
	$(LD) -m elf64btsmip -Tprog_link.ld -o $(OUT_DIR)/mem.elf $^
	cd $(OUT_DIR);\
	$(OBJCOPY) -S -O binary mem.elf mem.bin;\
	$(OBJDUMP) -xsSdD mem.elf > mem.dump;\
	$(MEMCONV);\
	cd ..
	cp $(OUT_DIR)/$@ ../../

$(OBJ_DIR)/init.o : init.s
	mkdir -p $(OBJ_DIR)
	$(AS) -EB -march=mips64 -mabi=64 -G0 -ggdb -o $@ $<
	$(OBJDUMP) -xsSd $@ > $(patsubst %.o,%.dump,$@)

$(OBJ_DIR)/main.s : main.c
	echo "building main with OPT=$(OPT)"
	$(CC) -march=mips64 -mabi=64 -S -I $(LIB_DIR) $(addprefix -I ,$(wildcard tests/*)) $(OPT) -o $@ $<

$(OBJ_DIR)/scatter_gather.o :
	$(MAKE) -C tests/scatter_gather

$(OBJ_DIR)/shared_array.o :
	$(MAKE) -C tests/shared_array

$(OBJ_DIR)/parallel_sort.o :
	$(MAKE) -C tests/parallel_sort

$(OBJ_DIR)/merge_sort.o :
	$(MAKE) -C tests/merge_sort

$(OBJ_DIR)/%.s : $(LIB_DIR)/%.c
	$(CC) -march=mips64 -mabi=64 -S -I $(CHERILIBS_DIR)/include -I $(LIB_DIR) $(OPT) -o $@ $<

$(OBJ_DIR)/%.o : $(OBJ_DIR)/%.s
	$(AS) -EB -march=mips64 -mabi=64 -G0 -ggdb -o $@ $<
	$(OBJDUMP) -xsSd $@ > $(patsubst %.o,%.dump,$@)

clean :
	$(MAKE)	-C tests/scatter_gather clean
	$(MAKE)	-C tests/shared_array clean
	$(MAKE)	-C tests/parallel_sort clean
	$(MAKE) -C tests/merge_sort clean
	rm -rf $(OBJ_DIR)

mrproper : clean
	rm -rf $(OUT_DIR)
