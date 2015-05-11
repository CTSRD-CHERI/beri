#!/usr/bin/make -f

#
# Copyright (c) 2013 Philip Withnall
# Copyright (c) 2013 Colin Rothwell
# Copyright (c) 2014 Alex Horsman
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


BSC = bsc
LIBS = ../../
BSCFLAGS = -keep-fires -cross-info -aggressive-conditions -show-range-conflict -p +:$(LIBS):$(LIBS)/peripherals/PixelStream
BSCFLAGS += $(BSC_DEFS) -bdir bdir
SUFFIXES =
VERILOGDEST = ../qsys_ip/Compositor
GENVERILOG = $(VERILOGDEST)/mkCompositorPhy.v
HW_TCL = $(VERILOGDEST)/CompositorPhy_hw.tcl

# Simulation. Set SIM_TOPLEVEL=TestCompositorOutput (for example) to run something other than TopSimulation.
# Set SIM_FLAGS=+debug (for example) to get debug output (also available as the `run-sim-debug` target).
SIM_FLAGS = +term-colour
DEBUG_FLAGS = +debug +compositor-controller +compositor-compositor +compositor-unit

# Simulation parameters for simulating the compositor alone.
SIM_TOPLEVEL = TopSimulation
SIM_BA_TOPLEVEL = ./bsim/mk$(SIM_TOPLEVEL).ba
SIM_BSV_TOPLEVEL = $(SIM_TOPLEVEL).bsv
SIM_TOPLEVEL_MODULE = mk$(SIM_TOPLEVEL)

BSV_FILES = \
	Compositor.bsv \
	CompositorMemoryRequest.bsv \
	CompositorMemoryResponse.bsv \
	CompositorOutput.bsv \
	CompositorPhy.bsv \
	CompositorTceRequest.bsv \
	CompositorTceResponse.bsv \
	CompositorUnit.bsv \
	CompositorUtils.bsv \
	TestUtils.bsv \
	TopSimulation.bsv \
	$(addsuffix .bsv,$(TESTS)) \
	$(NULL)
TESTS = \
	TestCompositor \
	TestCompositorMemoryRequest \
	TestCompositorMemoryResponse \
	TestCompositorOutput \
	TestCompositorTceRequest \
	TestCompositorTceResponse \
	TestCompositorUnit \
	TestCompositorUtils \
	$(NULL)

all: $(VERILOGDEST) $(GENVERILOG) $(HW_TCL)

$(VERILOGDEST):
	mkdir $(VERILOGDEST)

$(VERILOGDEST)/mkCompositorPhy.v: CompositorPhy.bsv
	$(BSC) $(BSCFLAGS) -vdir $(VERILOGDEST) -u -verilog -g mkCompositorPhy CompositorPhy.bsv

$(VERILOGDEST)/CompositorPhy_hw.tcl: CompositorPhy_hw.tcl
	cp CompositorPhy_hw.tcl $(VERILOGDEST)

# Cleaning things.
clean:
	rm -f  *.bi *.bo *.ba *.info *.sched *.h *.o *.so $(GENVERILOG) $(HW_TCL) >/dev/null
	rm -rf bdir/* $(SIM_TOPLEVEL_MODULE).sched >/dev/null
	rm -f *.ppm >/dev/null
.PHONY: clean

# Simulation (of the compositor alone).
$(SIM_BA_TOPLEVEL): $(BSV_FILES)
	$(BSC) $(BSCFLAGS) -simdir ./bsim -bdir ./bsim -u -sim -D BLUESIM -show-schedule $(SIM_BSV_TOPLEVEL)

sim: $(SIM_BA_TOPLEVEL)
	$(BSC) $(BSCFLAGS) -sim -e $(SIM_TOPLEVEL_MODULE) -simdir ./bsim -bdir ./bsim -o sim ./bsim/*.ba

run-sim: sim
	./sim $(SIM_FLAGS)
run-sim-debug:
	$(MAKE) run-sim SIM_FLAGS="$(SIM_FLAGS) $(DEBUG_FLAGS)"
.PHONY: run-sim run-sim-debug

# Unit testing.
check:
	for i in $(TESTS); do \
		$(MAKE) run-sim SIM_TOPLEVEL=$$i || exit 1; \
	done
.PHONY: check
