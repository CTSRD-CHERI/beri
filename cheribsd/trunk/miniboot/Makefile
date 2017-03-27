#-
# Copyright (c) 2012 Robert N. M. Watson
# Copyright (c) 2012-2013 Jonathan Woodruff
# Copyright (c) 2013 Bjoern A. Zeeb
# Copyright (c) 2016 Alexandre Joannou
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

CHERIROOT?=../../../cheri/trunk
CHERIROOT_ABS:=$(realpath $(CHERIROOT))
CHERILIBS?=../../../cherilibs/trunk
CHERILIBS_ABS:=$(realpath $(CHERILIBS))
CHERICONF?=simconfig
TOOLS_DIR=$(CHERILIBS)/tools
TOOLS_DIR_ABS:=$(realpath $(TOOLS_DIR))

CAPSIZE?=0
TAGS_STRUCT?="0"
TAGS_ALIGN?=32

MEMCONV=python "$(TOOLS_DIR_ABS)/memConv.py"
AS=mips64-as
CPP=cpp
LD=mips64-ld
OBJDUMP=mips64-objdump
OBJCOPY=mips64-objcopy

CFLAGS += -EB -march=mips64 -mabi=64 -G 0 -ggdb -O1 -S
ifdef ALWAYS_WAIT
CPPFLAGS += -DALWAYS_WAIT
endif

LDSCRIPT=miniboot.ld

.DUMMY=all
all: miniboot.elf mem.bin miniboot.dump

ifndef CHERIOS
miniboot.o : miniboot.S
	$(CPP) $(CPPFLAGS) miniboot.S miniboot.s
	$(AS) -EB -march=mips64 -mabi=64 -G0 -ggdb -o miniboot.o miniboot.s
else
miniboot.o : miniboot_cherios.S
	$(CPP) $(CPPFLAGS) miniboot_cherios.S miniboot_cherios.s
	$(AS) -EB -march=mips64 -mabi=64 -G0 -ggdb -o miniboot.o miniboot_cherios.s
endif
.PHONY: tags-params.ld
tags-params.ld: $(CHERILIBS)/tagsparams.py
	$^ -a $(TAGS_ALIGN) -c $(CAPSIZE) -s $(subst _,$(SPACE),$(TAGS_STRUCT:"%"=%)) -l $@
miniboot.elf : miniboot.o $(LDSCRIPT) $(CHERIROOT)/mem-params.ld tags-params.ld
	$(LD) -L$(CHERIROOT) -EB -G0 -T$(LDSCRIPT) $< -o $@ -m elf64btsmip
miniboot.mem : miniboot.elf
	$(OBJCOPY) -S -O binary $< $@
miniboot.dump : miniboot.elf
	$(OBJDUMP) -xsSD $< > $@

mem.bin: miniboot.mem
	cp $< $@
	$(MEMCONV)

run:
	LD_LIBRARY_PATH=$(CHERILIBS_ABS)/peripherals			\
	    CHERI_KERNEL=kernel						\
	    CHERI_CONFIG=$(CHERICONF)					\
	    ${CHERIROOT_ABS}/sim

trace:
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

clean:
	rm -f *.o *.i *.elf *.mem *.dump mem.bin mem?.hex initial.hex
	rm -f miniboot.s
	rm -f tags-params.ld
