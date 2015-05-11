#-
# Copyright (c) 2012-2013 Robert N. M. Watson
# Copyright (c) 2012-2013 Jonathan Woodruff
# Copyright (c) 2012-2013 Robert M. Norton
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
# Build environment for simboot.
#

CHERIROOT?=../../../cheri/trunk
CHERIROOT_ABS:=$(realpath $(CHERIROOT))
CHERILIBS?=../../../cherilibs/trunk
CHERILIBS_ABS:=$(realpath $(CHERILIBS))
CHERICONF?=simconfig
CHERI_SIM_OPTS?=+regDump +btrace +cTrace +instructionBasedCycleCounter
TOOLS_DIR=${CHERILIBS_ABS}/tools
TOOLS_DIR_ABS:=$(realpath $(TOOLS_DIR))
TRACE_NAMES_ABS:=$(TOOLS_DIR_ABS)/tracing/trace_names.py
KERNEL?=kernel
GZIP?=
COMPRESS_TRACE:=$(if $(GZIP),| gzip -c -,)
TRACE_SUFFIX:=$(if $(GZIP),.gz,)

MEMCONV=python $(TOOLS_DIR_ABS)/memConv.py
AS=mips64-as

LDSCRIPT=simboot.ld

.DUMMY=all
all: simboot.elf mem.bin simboot.dump

%.o : %.s
	$(AS) -EB -march=mips64 -mabi=64 -G0 -ggdb -o $@ $<
%.elf : %.o $(LDSCRIPT)
	mips64-ld -b elf64-bigmips -EB -G0 -T$(LDSCRIPT) $< -o $@
%.mem : %.elf
	mips64-objcopy -S -O binary $< $@
%.dump : %.elf
	mips64-objdump -xsSD $< > $@

# PHONY because KERNEL can change making dependency wrong
.PHONY: kernel_nm.txt
kernel_nm.txt: $(KERNEL)
	nm $(KERNEL) > $@

mem.bin: simboot.mem
	cp $< $@
	$(MEMCONV)

.PHONY: run
run: mem.bin
ifndef BERI_DEBUG_SOCKET_0
	@echo "Must set BERI_DEBUG_SOCKET_0 to use trace default target"
	@exit 1
endif
ifndef BERI_DEBUG_SOCKET_1
	@echo "Warning: BERI_DEBUG_SOCKET_1 not set, only the default target will be traced"
endif
ifndef CHERI_CONSOLE_SOCKET
	@echo "Warning: CHERI_CONSOLE_SOCKET not set, using stdio"
	LD_LIBRARY_PATH=$(CHERILIBS_ABS)/peripherals			\
	    CHERI_KERNEL=$(KERNEL)					\
	    CHERI_CONFIG=$(CHERICONF)					\
	    BERI_DEBUG_SOCKET_0=$(BERI_DEBUG_SOCKET_0)			\
	    BERI_DEBUG_SOCKET_1=$(BERI_DEBUG_SOCKET_1)			\
	    ${CHERIROOT_ABS}/sim
else
	LD_LIBRARY_PATH=$(CHERILIBS_ABS)/peripherals			\
	    CHERI_KERNEL=$(KERNEL)					\
	    CHERI_CONFIG=$(CHERICONF)					\
	    CHERI_CONSOLE_SOCKET=$(CHERI_CONSOLE_SOCKET)		\
	    BERI_DEBUG_SOCKET_0=$(BERI_DEBUG_SOCKET_0)			\
	    BERI_DEBUG_SOCKET_1=$(BERI_DEBUG_SOCKET_1)			\
	    ${CHERIROOT_ABS}/sim
endif

.PHONY: trace
trace: mem.bin
ifndef CHERI_TRACE_LOG
	@echo "Must set CHERI_TRACE_LOG to use trace target"
	@exit 1
endif
ifndef BERI_DEBUG_SOCKET_0
	@echo "Must set BERI_DEBUG_SOCKET_0 to use trace default target"
	@exit 1
endif
ifndef BERI_DEBUG_SOCKET_1
	@echo "Warning: BERI_DEBUG_SOCKET_1 not set, only the default target will be traced"
endif
ifndef CHERI_CONSOLE_SOCKET
	LD_LIBRARY_PATH=$(CHERILIBS_ABS)/peripherals			\
	    CHERI_KERNEL=$(KERNEL)					\
	    CHERI_CONFIG=$(CHERICONF)					\
	    BERI_DEBUG_SOCKET_0=$(BERI_DEBUG_SOCKET_0)			\
	    BERI_DEBUG_SOCKET_1=$(BERI_DEBUG_SOCKET_1)			\
	    ${CHERIROOT_ABS}/sim					\
	    $(CHERI_SIM_OPTS) $(COMPRESS_TRACE) > $(CHERI_TRACE_LOG)$(TRACE_SUFFIX)
else
	LD_LIBRARY_PATH=$(CHERILIBS_ABS)/peripherals			\
	    CHERI_KERNEL=$(KERNEL)					\
	    CHERI_CONFIG=$(CHERICONF)					\
	    CHERI_CONSOLE_SOCKET=$(CHERI_CONSOLE_SOCKET)		\
	    BERI_DEBUG_SOCKET_0=$(BERI_DEBUG_SOCKET_0)			\
	    BERI_DEBUG_SOCKET_1=$(BERI_DEBUG_SOCKET_1)			\
	    ${CHERIROOT_ABS}/sim					\
	    $(CHERI_SIM_OPTS) $(COMPRESS_TRACE) > $(CHERI_TRACE_LOG)$(TRACE_SUFFIX)
endif

annotate_trace: mem.bin kernel_nm.txt
ifndef CHERI_TRACE_LOG
	@echo "Must set CHERI_TRACE_LOG to use trace target"
	@exit 1
endif
ifndef BERI_DEBUG_SOCKET_0
	@echo "Must set BERI_DEBUG_SOCKET_0 to use trace default target"
	@exit 1
endif
ifndef BERI_DEBUG_SOCKET_1
	@echo "Warning: BERI_DEBUG_SOCKET_1 not set, only the default target will be traced"
endif
	LD_LIBRARY_PATH=$(CHERILIBS_ABS)/peripherals			\
	    CHERI_KERNEL=$(KERNEL)					\
	    CHERI_CONFIG=$(CHERICONF)					\
	    CHERI_CONSOLE_SOCKET=$(CHERI_CONSOLE_SOCKET)		\
	    BERI_DEBUG_SOCKET_0=$(BERI_DEBUG_SOCKET_0)			\
	    BERI_DEBUG_SOCKET_1=$(BERI_DEBUG_SOCKET_1)			\
	    ${CHERIROOT_ABS}/sim					\
	    $(CHERI_SIM_OPTS)						\
	    | $(TRACE_NAMES_ABS) --nm=kernel_nm.txt 			\
	    $(COMPRESS_TRACE) > $(CHERI_TRACE_LOG)$(TRACE_SUFFIX)

gxemul:
	../../../cheritest/trunk/tools/gxemul/CTSRD-CHERI-gxemul-8d92b42/gxemul -V -E oldtestmips -M 3072 $(KERNEL) simboot.elf

clean:
	rm -f *.o *.elf *.mem *.dump mem.bin mem?.hex initial.hex
