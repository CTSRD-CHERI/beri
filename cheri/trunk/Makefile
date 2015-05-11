#-
# Copyright (c) 2010 Gregory A. Chadwick
# Copyright (c) 2010-2014 Jonathan Woodruff
# Copyright (c) 2010-2011 Steven J. Murdoch
# Copyright (c) 2012 SRI International
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2011 Wojciech A. Koszek
# Copyright (c) 2011 Jonathan Anderson
# Copyright (c) 2011 Philip Paeps
# Copyright (c) 2012 Simon W. Moore
# Copyright (c) 2012-2013 Robert M. Norton
# Copyright (c) 2012 Ben Thorner
# Copyright (c) 2013-2014 Theo Markettos
# Copyright (c) 2013 Philip Withnall
# Copyright (c) 2013 Michael Roe
# Copyright (c) 2013-2014 Colin Rothwell
# Copyright (c) 2013 Bjoern A. Zeeb
# Copyright (c) 2013 Alan A. Mujumdar
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

CHERILIBS_DIR   ?= ../../cherilibs/trunk
TOOLS_DIR       = $(CHERILIBS_DIR)/tools
PERIPHERALS_DIR = $(CHERILIBS_DIR)/peripherals
INCLUDE_DIR     = $(CHERILIBS_DIR)/include
BUILD_DIR       = ./build
IP_DIR          = ./ip/

#TOPLEVEL = MIPSTop
# XXX: Avalon2ClientServer.bsv isn't necessary
BSV_FILES=			\
	Branch.bsv        \
	BranchSimple.bsv  \
	$(CHERILIBS_DIR)/BeriBootMem.bsv		\
	Merge.bsv	        \
	$(CHERILIBS_DIR)/L2Cache.bsv        \
	$(CHERILIBS_DIR)/MemTypes.bsv        \
	$(CHERILIBS_DIR)/Processor.bsv        \
	$(CHERILIBS_DIR)/TopAxi.bsv        \
	$(CHERILIBS_DIR)/TopSimAxi.bsv			\
	$(CHERILIBS_DIR)/CheriAxi.bsv			\
	$(CHERILIBS_DIR)/BlueBusWrapper.bsv		\
	$(CHERILIBS_DIR)/Interconnect.bsv		\
	$(CHERILIBS_DIR)/Peripheral.bsv      \
	$(CHERILIBS_DIR)/TagCache.bsv      \
	$(CHERILIBS_DIR)/TraceTypes.bsv      \
	ICache.bsv		\
	DCache.bsv  \
	CP0.bsv			\
	CP0Micro.bsv		\
	CoProX.bsv			\
	CapCop.bsv 	   \
	$(PERIPHERALS_DIR)/Compositor/*.bsv \
	FPU/*.bsv     \
	Decode.bsv		\
	Execute.bsv		\
	MemAccess.bsv		\
	Memory.bsv		\
	MIPS.bsv		\
	ForwardingPipelinedRegFile.bsv		\
	MIPSTop.bsv		\
	ResetBuffer.bsv \
	Scheduler.bsv		\
	TLB.bsv			\
	Writeback.bsv			\
	DebugUnit.bsv		\
	Multicore.bsv

C_HEADERS=$(INCLUDE_DIR)/parameters.h

PISM_LIB= $(PERIPHERALS_DIR)/libpism.so

EXTRA_LINK=				\
	$(PERIPHERALS_DIR)/pismdev/debug_stream/debug_stream.c	\

all: sim vsim

.PHONY: FORCE
FORCE:

$(PISM_LIB): FORCE
	$(MAKE) -C $(PERIPHERALS_DIR) pism

CFLAGS=-g
BSVPATH=+:%/Libraries/TLM3:%/Libraries/Axi:%/Libraries/Contrib/NonPipelinedMath
BSVPATH:=$(BSVPATH):$(PERIPHERALS_DIR)/UART
BSVPATH:=$(BSVPATH):$(PERIPHERALS_DIR)/LoopbackUART:$(PERIPHERALS_DIR)/EtherCAP
BSVPATH:=$(BSVPATH):$(PERIPHERALS_DIR)/PixelStream:$(PERIPHERALS_DIR)/Compositor
BSVPATH:=$(BSVPATH):FPU:FPU/megafunctions:$(CHERILIBS_DIR)
BSVPATH:=:$(BSVPATH):$(CHERILIBS_DIR)/debugging
BSC_SIM_LIBS=
BSCFLAGS=-p $(BSVPATH) +RTS -K4000M -RTS
BSCFLAGS+= -no-warn-action-shadowing -show-schedule #-unspecified-to X -opt-undetermined-vals #-O

ifdef NOT_FLAT
BSCFLAGS+=-D NOT_FLAT
endif
ifdef WITH_COMPOSITOR
# FIXME: aggressive-conditions is needed for flow control between the processor
# and compositor to work correctly. The compositor needs rewriting to work
# without aggressive-conditions.
BSCFLAGS+=-D CHERI_COMPOSITOR -aggressive-conditions

ifdef WITH_COMPOSITOR_STATISTICS
# Enable statistics collection in the compositor. This doesn't affect timing,
# but does add register overhead.
BSCFLAGS+=-D CHERI_COMPOSITOR_STATISTICS
endif # WITH_COMPOSITOR_STATISTICS

ifdef WITH_COMPOSITOR_NO_OUTPUT
# Disable pixel output from the compositor, and drain all output pixels from it
# as fast as possible. This is for performance measurement purposes only. It
# certainly doesn’t make the screen look interesting.
BSCFLAGS+=-D CHERI_COMPOSITOR_NO_OUTPUT
endif # WITH_COMPOSITOR_NO_OUTPUT
endif # WITH_COMPOSITOR

BSC = bsc $(BSCFLAGS)
YACC = bison
YFLAGS = -yd

.PHONY: all debug sw pism_modules clean vsim synth test verilog print-versions version.hex megawizard

# Default to terasic_de4 for now.
BOARD_NAME=terasic_de4
ifdef BOARD
BOARD_NAME=$(BOARD)
endif

print-versions:
	$(BSC) -print-expiration | head -n1
	cd sw && $(MAKE) print-versions
	cd ../../cheritest/trunk && $(MAKE) print-versions

EXTRACTINFO=$(TOOLS_DIR)/cheri_genfiles.py

ifdef CAP
IP_DIR := $(IP_DIR)cheri
else
IP_DIR := $(IP_DIR)beri
endif

ifdef GENERICL1
BLUESPEC_FLAGS += -D GENERICL1
BSV_FILES += $(CHERILIBS_DIR)/AsymmetricBRAM/AsymmetricBRAM.bsv
EXTRA_LINK += $(CHERILIBS_DIR)/AsymmetricBRAM/mem_model.c
BSVPATH := :$(BSVPATH):$(CHERILIBS_DIR)/AsymmetricBRAM
endif

ifdef MULTI
BLUESPEC_FLAGS += -D MULTI -D CORE_COUNT_IN=$(MULTI)
BUILD_DIR := $(BUILD_DIR)_multi_$(MULTI)
endif

ifdef WITH_NOCACHE
BLUESPEC_FLAGS += -D NOCACHE
BUILD_DIR := $(BUILD_DIR)_noCache
endif

ifdef MICRO
BLUESPEC_FLAGS += -D MICRO
BUILD_DIR := $(BUILD_DIR)_micro
IP_DIR := $(IP_DIR)_micro
endif

ifdef NOBRANCH
BLUESPEC_FLAGS += -D NOBRANCHPREDICTION
BUILD_DIR := $(BUILD_DIR)_noBranch
endif

ifdef NOTAG
BLUESPEC_FLAGS += -D NOTAG
BUILD_DIR := $(BUILD_DIR)_noTag
endif

ifdef HARDCALL
BLUESPEC_FLAGS += -D HARDCALL
BUILD_DIR := $(BUILD_DIR)_hardCall
IP_DIR := $(IP_DIR)_hardCall
endif

ifdef COP1
BLUESPEC_FLAGS += -D COP1
BSC_SIM_LIBS += -l mpfr -l gmp
BUILD_DIR := $(BUILD_DIR)_fpu
IP_DIR := $(IP_DIR)_fpu
endif

ifdef COP3
BLUESPEC_FLAGS += -D COP3
BUILD_DIR := $(BUILD_DIR)_cop3
endif

ifdef CAP
BLUESPEC_FLAGS += -D CAP
BUILD_DIR := $(BUILD_DIR)_cap
endif

ifdef TRACE
BLUESPEC_FLAGS += -D TRACE
BUILD_DIR := $(BUILD_DIR)_trace
IP_DIR := $(IP_DIR)_trace
endif

IP_NAME := $(shell echo $$(basename $(IP_DIR)) | tr '[:lower:]' '[:upper:]')

verilog: BUILD_DIR := $(BUILD_DIR)_verilog

BLUESPEC_SIM_FLAGS += -D BLUESIM -D DEBUG_INST
BSC_SIM_FLAGS += -Xl -Wl,-rpath=$(PERIPHERALS_DIR) -L $(PERIPHERALS_DIR) -l pism

# Avalon Case Variable Names
PHYS_TOPLEVEL = TopAxi
PHYS_VERILOG_TOPLEVEL = $(IP_DIR)/mk$(PHYS_TOPLEVEL).v
PHYS_BA_TOPLEVEL = $(BUILD_DIR)/mk$(PHYS_TOPLEVEL).ba
PHYS_BSV_TOPLEVEL = $(CHERILIBS_DIR)/$(PHYS_TOPLEVEL).bsv
PHYS_TOPLEVEL_MODULE = mk$(PHYS_TOPLEVEL)
# Simulation Case Variable Names
SIM_TOPLEVEL = TopSimAxi
SIM_BA_TOPLEVEL = $(BUILD_DIR)/mk$(SIM_TOPLEVEL).ba
SIM_BSV_TOPLEVEL = $(CHERILIBS_DIR)/$(SIM_TOPLEVEL).bsv
SIM_TOPLEVEL_MODULE = mk$(SIM_TOPLEVEL)

$(PHYS_VERILOG_TOPLEVEL): $(PHYS_BSV_TOPLEVEL) $(BSV_FILES) megawizard
	mkdir -p $(BUILD_DIR)
	mkdir -p $(IP_DIR)
	$(BSC) -unspecified-to X -opt-undetermined-vals -vdir $(IP_DIR) -simdir $(BUILD_DIR) -bdir $(BUILD_DIR) -u -verilog $(BLUESPEC_FLAGS) $(PHYS_BSV_TOPLEVEL)
	cp $(CHERILIBS_DIR)/BRAM2Load.v $(IP_DIR)/
ifeq ($(MULTI),2)
	cp ip_include/dualcore_hw.tcl $(IP_DIR)/$(IP_NAME)_hw.tcl
else
	cp ip_include/hw.tcl $(IP_DIR)/$(IP_NAME)_hw.tcl
endif
ifdef COP1
	cp FPU/QuartusProject/*.* $(IP_DIR)/
#	cp ip_include/fpu/* $(IP_DIR)/
endif
ifdef GENERICL1
	cp $(CHERILIBS_DIR)/AsymmetricBRAM/*.v $(IP_DIR)/ 
endif
	echo "#!/bin/sh" > rename_qsys.sh
	echo "sed 's/BERI/$(IP_NAME)/g' < \$$1 > \$$2 " >> rename_qsys.sh
	chmod +x rename_qsys.sh
	# output a script to rename the Qsys instantiation to match the module being generated
#	echo "#!/usr/bin/env python" > rename_qsys.py
#	echo "import Qsys,sys" >> rename_qsys.py
#	echo "q = Qsys.Qsys(sys.argv[1])" >> rename_qsys.py
#	echo "q.renameComponent(\"BERI\",\"$(IP_NAME)\")" >> rename_qsys.py
#	echo "q.writeQsys(sys.argv[2])" >> rename_qsys.py

$(PHYS_BA_TOPLEVEL): $(BSV_FILES)
	mkdir -p $(BUILD_DIR)
	$(BSC) -simdir $(BUILD_DIR) -bdir $(BUILD_DIR) -u -sim $(BLUESPEC_FLAGS) -show-schedule $(PHYS_BSV_TOPLEVEL)

mem64.hex: sw

BUILD_DIR_SIM = $(BUILD_DIR)_sim

sim sim.so: $(BUILD_DIR_SIM)/sim $(BUILD_DIR_SIM)/sim.so FORCE
	rm -f sim sim.so
	ln -s $(BUILD_DIR_SIM)/sim sim
	ln -s $(BUILD_DIR_SIM)/sim.so sim.so

$(BUILD_DIR_SIM)/sim $(BUILD_DIR_SIM)/sim.so: $(BSV_FILES) $(PISM_LIB) mem64.hex
	mkdir -p $(BUILD_DIR_SIM)
	$(BSC) $(BSC_SIM_FLAGS) $(BSC_SIM_LIBS) -simdir $(BUILD_DIR_SIM) -bdir $(BUILD_DIR_SIM) -u -sim $(BLUESPEC_FLAGS) $(BLUESPEC_SIM_FLAGS)-show-schedule $(SIM_BSV_TOPLEVEL)
	$(BSC) $(BSC_SIM_FLAGS) $(BSC_SIM_LIBS) -sim -e $(SIM_TOPLEVEL_MODULE) -simdir $(BUILD_DIR_SIM) -bdir $(BUILD_DIR_SIM) -o $(BUILD_DIR_SIM)/sim $(BUILD_DIR_SIM)/*.ba $(EXTRA_LINK)

test: sim
	cd ../../cheritest/trunk && $(MAKE) CHERIROOT=../../cheri/trunk test

jenkins_test: print-versions run
	cd ../../cheritest/trunk && \
            $(MAKE) nosetest CHERIROOT=../../cheri/trunk NOSEFLAGS="--with-xunit --xunit-file=nosetests.xml" && \
            $(MAKE) nosetest_cached CHERIROOT=../../cheri/trunk NOSEFLAGS="--with-xunit --xunit-file=nosetests_cached.xml" 

GXEMUL_BINDIR=/usr/groups/ctsrd/gxemul/CTSRD-CHERI-gxemul-testversion
jenkins_test_gxemul: print-versions
	cd ../../cheritest/trunk && \
            $(MAKE) gxemul-nosetest GXEMUL_BINDIR=$(GXEMUL_BINDIR) CHERIROOT=../../cheri/trunk NOSEFLAGS="--with-xunit --xunit-file=nosetests.xml" && \
            $(MAKE) gxemul-nosetest_cached GXEMUL_BINDIR=$(GXEMUL_BINDIR) CHERIROOT=../../cheri/trunk NOSEFLAGS="--with-xunit --xunit-file=nosetests.xml"

verilog: $(PHYS_VERILOG_TOPLEVEL) miniboot version.hex

sw: $(C_HEADERS)
	$(MAKE) -C sw/helloworld

miniboot: ../../cheribsd/trunk/miniboot/miniboot.S
	cd ../../cheribsd/trunk/miniboot && $(MAKE)
	cp -r ../../cheribsd/trunk/miniboot/mem64.hex $(IP_DIR)/

synth: $(PHYS_VERILOG_TOPLEVEL)
	(cd boards/$(BOARD_NAME) && make synth)
program:
	(cd boards/$(BOARD_NAME) && make program)
run:
	bash -c 'time echo -n "LADQ" | ./sim -m 300000 2>&1'

megawizard:
	$(MAKE) -C FPU/QuartusProject megawizard

#
# Developer section and development targets for testing
#
pism:	$(PISM_C_FILES) $(CHERICONF_FILES) $(PERIPHERALS_DIR)/pism.h
	$(CC) $(CFLAGS) -DPISM_TEST_PROG -std=c99 -Wall -pedantic -I $(INCLUDE_DIR) -o pism $(PISM_C_FILES) $(CHERICONF_FILES)

ifdef GENERICL1
$(CHERILIBS_DIR)/AsymmetricBRAM/mem_model.o: $(CHERILIBS_DIR)/AsymmetricBRAM/mem_model.c
	$(CC) -fPIC -c $< -o $@
endif

peripherals: pism_modules
pism_modules:
	$(MAKE) -C $(PERIPHERALS_DIR)

version.hex:
	tclsh $(TOOLS_DIR)/versionHexGenerate.tcl	
	cp version.hex boards/terasic_de4/version.hex	
clean:
	rm -rf ./build*
	rm -f *.sched
	rm -f .vcsmx_rebuild
	rm -f sim
	rm -f sim.so
	rm -f sim.out
	rm -f mem.bin
	rm -rf ./csrc/
	rm -rf ./ip/*
	rm -f $(CHERILIBS_DIR)/*.bo
	rm -f $(CHERILIBS_DIR)/*.bi
	rm -f *.o
	rm -f *.hex
	rm -f mkRegFile.v
	rm -f rename_qsys.py
	rm -f pism
	rm -f $(CHERILIBS_DIR)/AsymmetricBRAM/mem_model.o
	$(MAKE) -C $(PERIPHERALS_DIR) clean
	$(MAKE) -C FPU/QuartusProject clean
	cd sw && $(MAKE) clean
