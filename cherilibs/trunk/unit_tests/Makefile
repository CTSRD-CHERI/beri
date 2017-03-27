#-
# Copyright (c) 2014 Alexandre Joannou
# Copyright (c) 2014 Colin Rothwell
# Copyright (c) 2016 A. Theodore Markettos
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

TESTS += TestAsymmetricBRAM
TESTS += TestBeriUGBypassFIFOF
TESTS += TestMEM
TESTS += TestOneWayBus
TESTS += TestBus
TESTS += TestCrossBar
TESTS += TestReorderBuffer
TESTS += TestSingleMasterOrderedBus
TESTS += TestTLMRoutableInstances
TESTS += TestDMA
TESTS += TestDMAICache
TESTS += TestOrderedBus
TESTS += TestDebugModule

ASYMMETRIC_BRAM_DIR = ../AsymmetricBRAM
CHERI_DIR = ../../../cheri/trunk
CHERILIBS_DIR = ..
DMA_DIR=$(CHERILIBS_DIR)/peripherals/DMA

BSC = bsc
BSV_PATH = +:%/Libraries/TLM3:%/Libraries/Axi:$(CHERILIBS_DIR):$(ASYMMETRIC_BRAM_DIR):../debugging
BSV_PATH:=$(BSV_PATH):$(DMA_DIR):$(CHERI_DIR)
BSC_FLAGS=-keep-fires -p $(BSV_PATH)
BSC_FLAGS+=-u
BSC_FLAGS+=-bdir elab
BSC_FLAGS+=-simdir bsim
BSC_FLAGS+=-sched-dot -show-schedule -info-dir info
BSC_FLAGS+=-check-assert
BSC_FLAGS+=-suppress-warnings G0043 # reset domains
BSC_FLAGS+=+RTS -K4000000000 -RTS # ~ 4GB
SIMFLAGS=-sim -D BLUESIM

all : $(addprefix sim/,$(TESTS))

run-% : sim/%
	$<

sim/% : %.bsv
	mkdir -p sim
	mkdir -p elab
	mkdir -p bsim
	mkdir -p info
	$(BSC) $(BSC_FLAGS) $(SIMFLAGS) -g mk$(notdir $@) $<
	$(BSC) $(BSC_FLAGS) $(SIMFLAGS) -e mk$(notdir $@) -o $@

sim/TestInternalMemoryToInterconnect: ../CheriAxi.bsv

sim/TestDMA: $(DMA_DIR)/DMA.bsv ../InflightCounter.bsv ../TwoWritePortRegFile.bsv

sim/TestDMAICache: $(DMA_DIR)/DMAICache.bsv

sim/TestOrderedBus: ../Interconnect.bsv

sim/TestAsymmetricBRAM : TestAsymmetricBRAM.bsv bsim/mem_model.o
	mkdir -p sim
	mkdir -p elab
	mkdir -p bsim
	mkdir -p info
	$(BSC) $(BSC_FLAGS) $(SIMFLAGS) -g mk$(notdir $@) $<
	$(BSC) $(BSC_FLAGS) $(SIMFLAGS) -e mk$(notdir $@) -o $@ bsim/mem_model.o

bsim/mem_model.o : $(ASYMMETRIC_BRAM_DIR)/mem_model.c
	echo "compiling $@"
	mkdir -p bsim
	$(CC) -fPIC -c $< -o $@

clean :
	rm -rf sim/
	rm -rf elab/
	rm -rf bsim/
	rm -rf info/
