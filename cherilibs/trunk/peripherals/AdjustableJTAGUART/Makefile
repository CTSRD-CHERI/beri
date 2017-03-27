#!/usr/bin/make -f
#-
# Copyright (c) 2013 Simon W. Moore
# Copyright (c) 2016, 2017 A. Theodore Markettos
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

# Generate a version of Altera's Avalon JTAG UART where the instance ID is
# accessible as a parameter.  This means we can pin UARTs to specific
# instance IDs, and don't risk them randomly getting assigned at synthesis time
#
# This patch is based on Quartus 16.0 - it may need tweaking for other versions
#
# The current implementation is somewhat unfortunate because we have to set the
# FIFO sizes here, not in the qsys GUI.  This is because we have to provide those
# as parameters to ip-generate that makes Verilog. We then patch the verilog and
# present it as a component to qsys.
#
# Ideally instead we want to patch
# ip/altera/sopc_builder_ip/altera_avalon_jtag_uart/altera_avalon_jtag_uart_hw.tcl
# from the Quartus distro so that it exposes the instance ID.
# Unfortunately we can't commit a changed version for licence reasons, but a patch
# may be feasible.

VERILOGDEST=../qsys_ip/AdjustableJTAGUART
VERILOG_VANILLA=vanilla_jtag_uart
VERILOG_PATCHED=adjustable_jtag_uart
GENVERILOG=$(VERILOG_PATCHED).v
HW_TCL_A=$(VERILOG_PATCHED)_hw.tcl
PATCHFILE=jtag_uart_instance_id.p

all: $(VERILOGDEST) $(VERILOGDEST)/$(GENVERILOG) $(VERILOGDEST)/$(HW_TCL_A)

$(VERILOG_VANILLA)/$(VERILOG_VANILLA).v:
	ip-generate --file-set=QUARTUS_SYNTH --component-name=altera_avalon_jtag_uart \
		-cp=readBufferDepth=4096 -cp=writeBufferDepth=512 \
		--output_name=$(VERILOG_VANILLA)

$(VERILOG_PATCHED).v: $(VERILOG_VANILLA)/$(VERILOG_VANILLA).v
	patch -p0 -i $(PATCHFILE)
	sed s/vanilla/adjustable/g < $(VERILOG_VANILLA)/$(VERILOG_VANILLA).v > $(VERILOG_PATCHED).v

$(VERILOGDEST):
	mkdir $(VERILOGDEST)

$(VERILOGDEST)/$(GENVERILOG): $(VERILOGDEST) $(GENVERILOG)
	cp $(GENVERILOG) $(VERILOGDEST)

$(VERILOGDEST)/$(HW_TCL_A): $(HW_TCL_A)
	cp $(HW_TCL_A) $(VERILOGDEST)

.PHONY: clean
clean:
	rm -f  *~ *.bi *.bo *.ba *.info *.sched *.h *.o *.so *.cxx
	rm -rf $(VERILOGDEST) $(VERILOG_VANILLA) $(VERILOG_PATCHED).v
