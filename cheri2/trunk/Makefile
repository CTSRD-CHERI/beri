#-
# Copyright (c) 2011 Jonathan Woodruff
# Copyright (c) 2011-2013 SRI International
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

##############################################################################
# CTSRD FILE STRUCTURE
##############################################################################

CAP_DIR         ?= Cap
CHERILIBS_DIR   ?= ../../cherilibs/trunk
TOOLS_DIR       = $(CHERILIBS_DIR)/tools
PERIPHERALS_DIR = $(CHERILIBS_DIR)/peripherals
BDIR            = bdir$(CONFIG_STRING)
SIMDIR          = simdir$(CONFIG_STRING)
SIMBIN          = $(SIMDIR)/sim
VDIR            = ip/cheri2/

##############################################################################
# CHERI2 Config Options
#
# CHERI2 has many configuration options which can be individually
# set. These are gathered here as a set of make variables which can be
# be overridden on the command line, or by the various named targets
# below (e.g. sim_cap).
#
# The options are passed to BlueSpec as a set of macro defines, and also
# concatenated into a string which is used as the name of the directory to
# build in. This ensures that changing the options will always cause a
# rebuild, so no need to make clean. After the build sim and sim.so in this
# directory are symlinked to the simulator which was just built.
#
# The defaults are designed to be the common case so an empty config string
# should do something sensible. To find the default values you'll have to
# grep the .bsv files...
#
# Note that for boolean options the only values that matter are empty and
# non-empty, so CAP=0 and CAP=1 have the same effect of enabling
# capabilities.
#
##############################################################################

# Since the debug unit takes time to compile, area and can affect
# timing it can be disabled.
DEBUG ?=
# For formal verification some modules are substituted for ones with
# simpler, less performant implementaions.
VERIFY ?=
VERIFY2 ?=
# Optional support for capabilities.
CAP ?=
# The current implementation of watch points in Cheri2 causes
# significant expansion of the control token. Since this is
# undesirable and watchpoints are rarely used this feature is
# optional.
NOWATCH ?=
# Sometimes it is useful to terminate the simulation after a specified
# number of instructions (not cycles). Set this to non-zero to enable
# this.
INSTR_LIMIT ?=
# Sometimes it is useful for debugging if the cycle counter is
# deterministic.  If enabled this option increments the MIPS counter
# register every instruction commited rather than every cycle.
DETERMINISTIC_TIMER ?=
# Similarly it can be a useful diagnostic to emulate an unpipelined
# processor by ensuring that there is at most one instruction in the
# pipeline at at time.
UNPIPELINE ?=
# Enable this option to use a simpler, fully-associative TLB. This
# probably has poor area and timing properties and definitely no
# support for multi-threading.
SIMPLE_TLB ?=
# Enable support for CP1X (for open flow switch). Rotten.
CP1X ?=
# Define number of bits of ThreadID, i.e. log2 of number of threads.
# e.g. 0 => 1 thread, 1 => 2 threads, 2 => 4 threads etc.
THREADSZ ?= 0
# Number of ways in the instruction and data caches.
IWAYS ?=
DWAYS ?=
# Number of bits of index for TLB i.e. log2 of number of entries (per thread).
# Maximum supported by MIPS is 6 (64 entries).
TLBSIZE ?=
# Thread to debug with debug unit (statically defined for now).
DEBUGTHREAD ?=
# Build without an L2 cache
NOL2 ?=
# Build without tag support -- tagcache always return true!
NOTAG ?=

#These options not supported yet.
#SEGBITS
#PABITS
#PAGEBITS

# Whether to run tests which use clang.
CLANG ?= 0

OPTS=\
$(if $(DEBUG), DEBUG)\
$(if $(CAP), CAP)\
$(if $(VERIFY), VERIFY)\
$(if $(VERIFY2), VERIFY2)\
$(if $(NOWATCH), NOWATCH)\
$(if $(CP1X), CP1X)\
$(if $(INSTR_LIMIT), INSTR_LIMIT=$(INSTR_LIMIT))\
$(if $(DETERMINISTIC_TIMER), DETERMINISTIC_TIMER)\
$(if $(UNPIPELINE), UNPIPELINE)\
$(if $(SIMPLE_TLB), SIMPLE_TLB) \
$(if $(THREADSZ), THREADSZ=$(THREADSZ)) \
$(if $(IWAYS), IWAYS=$(IWAYS)) \
$(if $(DWAYS), DWAYS=$(DWAYS)) \
$(if $(TLBSIZE), TLBSIZE=$(TLBSIZE)) \
$(if $(DEBUGTHREAD), DEBUGTHREAD=$(DEBUGTHREAD)) \
$(if $(NOL2), NOL2) \
$(if $(NOTAG), NOTAG)
# Behold! The beauty of make!
empty=
space=$(empty) $(empty)

CONFIG_BSC_DEFS=$(foreach opt,$(OPTS),-D $(opt))
CONFIG_STRING=$(subst $(space),,$(foreach opt,$(OPTS),_$(opt)))


##############################################################################
# Bluespec
##############################################################################

BSCFLAGS=-u
#BSCFLAGS+=-aggressive-conditions
BSCFLAGS+=-scheduler-effort 10000
BSCFLAGS+=-no-warn-action-shadowing
BSCFLAGS+=-sat-yices
BSCFLAGS+=-keep-fires
BSCFLAGS+=-keep-inlined-boundaries
BSCFLAGS+=-parallel-sim-link $$(nproc)
BSCFLAGS+=-check-assert
#BSCFLAGS+=-bug-debug
BSCFLAGS+=-show-schedule
#BSCFLAGS+=-dschedule
#BSCFLAGS+=-show-range-conflict
#BSCFLAGS+=-sched-dot
#BSCFLAGS+=-show-rule-rel \* \*
#BSCFLAGS+=-show-elab-progress
BSCFLAGS+=-suppress-warnings G0010:G0020:S0081:S0089:G0024:T0127
BSCFLAGS+= -opt-undetermined-vals
# for some reason stack usage increases dramatically with higher THREADSZ
BSCFLAGS+=+RTS -K64M -RTS

BSCPATH=%/Libraries/TLM3
BSCPATH+=%/Libraries/Axi
BSCPATH+=$(CAP_DIR)
BSCPATH+=$(CHERILIBS_DIR)
BSCPATH+=$(PERIPHERALS_DIR)/LoopbackUART
BSCPATH+=$(PERIPHERALS_DIR)/Compositor
BSCPATH+=$(PERIPHERALS_DIR)/PixelStream

BSCFLAGS+=-p +:$(subst $(space),:,$(BSCPATH))
BSCFLAGS+=-Xl -Wl,-rpath=$(PERIPHERALS_DIR) -L $(PERIPHERALS_DIR) -l pism
BSCFLAGS+= -bdir $(BDIR) -simdir $(SIMDIR) -vdir $(VDIR)
BSCFLAGS+= --wait-for-license
BSCFLAGS+=$(CONFIG_BSC_DEFS)

# use gcc-4.5 because 4.6 is borked.
#BSC = CC=gcc-4.5 CXX=gcc-4.5 time bsc $(BSCFLAGS)
BSC = time bsc $(BSCFLAGS)

##############################################################################
# FPGA Setup
##############################################################################

# Default to terasic_de4 for now.
BOARD_NAME=terasic_de4
ifdef BOARD
BOARD_NAME=$(BOARD)
endif

EXTRACTINFO=$(TOOLS_DIR)/cheri_genfiles.py
FPGADATAFILE=boards/$(BOARD_NAME)/DE4_SOPC.sopc

##############################################################################
# PISM
##############################################################################

all: sim

.PHONY: FORCE

FORCE:

PISM_LIB= $(PERIPHERALS_DIR)/libpism.so

$(PISM_LIB): FORCE
	$(MAKE) -C $(PERIPHERALS_DIR) pism

EXTRA_LINK = $(PERIPHERALS_DIR)/pismdev/debug_stream/debug_stream.c	\

##############################################################################
# CHERI2 Build
##############################################################################

TOP_SIM_BSV=$(CHERILIBS_DIR)/TopSimAxi.bsv
TOP_AXI_BSV=$(CHERILIBS_DIR)/TopAxi.bsv
SIM_DTS_IN=$(CHERILIBS_DIR)/peripherals/sim.dts.in

.PHONY: sim vsim sim_debug vsim_debug sim_cap vsim_cap

DTS_CPP_FLAGS=$(CONFIG_BSC_DEFS)

sim: $(PISM_LIB)
	mkdir -p $(SIMDIR)
	mkdir -p $(BDIR)
	$(BSC) -sim -g mkTopSimAxi $(TOP_SIM_BSV)
	$(BSC) -sim -e mkTopSimAxi -o $(SIMBIN) $(EXTRA_LINK)
	cpp $(DTS_CPP_FLAGS) -x assembler-with-cpp -include $(SIM_DTS_IN) /dev/null | \
	    grep -v '^# [0-9]* "' > $(SIMDIR)/sim.dts.cpp
	$(TOOLS_DIR)/process-dts.sh $(SIMDIR)/sim.dts.cpp $(SIMDIR)/sim.dts
	dtc -O dtb -o $(SIMDIR)/sim.dtb -b 0 $(SIMDIR)/sim.dts
	ln -sf $(SIMBIN) .
	ln -sf $(SIMBIN).so .
	ln -sf $(SIMDIR)/sim.dtb .

vsim:
	$(BSC) -verilog -g mkTopSimAxi $(TOP_SIM_BSV)
	$(BSC) -verilog -e mkTopSimAxi -o sim *.v

sim_debug: DEBUG=1
sim_debug: sim

vsim_debug: DEBUG=1
vsim_debug: vsim

sim_cap: CAP=1
sim_cap: sim

sim_cap_debug: DEBUG=1
sim_cap_debug: CAP=1
sim_cap_debug: sim

sim_cap_cp1x: CAP=1
sim_cap_cp1x: DEBUG=1
sim_cap_cp1x: CP1X=1
sim_cap_cp1x: sim

vsim_cap: CAP=1
vsim_cap: DEBUG=1
vsim_cap: vsim

verilog: BSCFLAGS+=-unspecified-to X
verilog:
	mkdir -p $(SIMDIR)
	mkdir -p $(BDIR)
	$(BSC) -verilog -g mkTopAxi $(TOP_AXI_BSV)

verilog_debug: DEBUG=1
verilog_debug: verilog

verilog_debug_unpipelined: DEBUG=1
verilog_debug_unpipelined: UNPIPELINE=1
verilog_debug_unpipelined: verilog

sim_cap_dumpsmten: CAP=1
sim_cap_dumpsmten: VERIFY=1
sim_cap_dumpsmten: VERIFY2=1
sim_cap_dumpsmten:
	mkdir -p $(SIMDIR)
	mkdir -p $(BDIR)
	$(BSC) -sim -ddumpLambdaCalculus=MOD_%m.smtncolon -g mkCheri Proc.bsv
	echo '{-# LANGUAGE DataKinds, ScopedTypeVariables #-}' > MOD_mkCheri.hs
	echo "module MOD_mkCheri where\n\nimport Smten.Prelude\nimport BSVPrelude\nimport Smten.Symbolic\n" >> MOD_mkCheri.hs
	cat MOD_*.smtncolon | perl -pe 's/\;[\n]/\n/g' | perl -pe 's/#//g' >> MOD_mkCheri.hs

sim_cap_verify: DEBUG=1
sim_cap_verify: CAP=1
sim_cap_verify: SIMPLETLB=1
sim_cap_verify: VERIFY=1
sim_cap_verify: sim


sim_verify: DEBUG=1
sim_verify: SIMPLETLB=1
sim_verify: VERIFY=1
sim_verify: sim

sim_cap_cp1x_verify: CAP=1
sim_cap_cp1x_verify: DEBUG=1
sim_cap_cp1x_verify: CP1X=1
sim_cap_cp1x_verify: VERIFY=1
sim_cap_cp1x_verify: sim

##############################################################################
# Bluespec Linting Checks
##############################################################################

sim_lint:
	$(BSC) -Werror -g mkTopSimulation $(TOP_SIM_BSV)
	$(BSC) -sim -e mkTopSimulation -o sim *.ba $(EXTRA_LINK)

vsim_lint:
	$(BSC) -Werror -verilog -g mkTopAxi TopAxi.bsv

##############################################################################
# Testing Infrastructure
##############################################################################

print-versions:
	$(BSC) -print-expiration | head -n1
	cd ../../cheritest/trunk && $(MAKE) print-versions

run_tests:
	cd ../../cheritest/trunk && $(MAKE) -j $$(nproc) BERI_VER=2 CLANG=$(CLANG) nosetest_cached

test: sim_cap_debug run_tests

jenkins_test: print-versions sim_cap run
	cd ../../cheritest/trunk && \
            $(MAKE) nosetest CHERIROOT=../../cheri2/trunk NOSEFLAGS="--with-xunit --xunit-file=nosetests.xml" && \
            $(MAKE) nosetest_cached CHERIROOT=../../cheri2/trunk NOSEFLAGS="--with-xunit --xunit-file=nosetests_cached.xml"

run:
	bash -c 'time echo -n "LADQ" | ./sim -m 300000 2>&1'

gen_mem:
	python $(TOOLS_DIR)/memConv.py bsim

##############################################################################
# Cleanup
##############################################################################

SUBD = $(filter %/, $(shell ls -F))
SUBDIRS ?= $(SUBD)

clean:
	${RM} -r *.b[ioa] *.smtncolon *.smten *.hs *.sched mk*.v mk*.o mk*.cxx mk*.h schedule.cxx schedule.[ho] *.seri sim.so sim model_mk*.[ho] model_mk*.cxx $(VDIR)/mk*.v simdir*/ bdir*/
ifneq ($(SUBDIRS),)
	@for dir in ${SUBDIRS} ; do \
	if [ -f $$dir/Makefile ]; then echo "cleaning $$dir" && \
	${MAKE} -C $$dir clean; fi ; done
endif
	${MAKE} -C ${CHERILIBS_DIR} clean
	${MAKE} -C ${PERIPHERALS_DIR} clean

tidy:
	rm -f *~ \#*
ifneq ($(SUBDIRS),)
	@for dir in ${SUBDIRS} ; do \
	[ -f $$dir/Makefile ] && echo "cleaning $$dir" && \
	${MAKE} -C $$dir tidy ; done
endif
