#!/usr/bin/make -f
#-
# Copyright (c) 2013 Simon W. Moore
# Copyright (c) 2014 Jonathan Woodruff
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

BSC=bsc
LIBS=../../
BSVINC=$(LIBS)/Avalon2ClientServer.bsv
BSVSRC=USB1761Bridge.bsv
BSVTOP=mkUSB1761Bridge
BSVTST=USB1761Bridge.bsv
BSVTST_TOPMOD=mkUnitTestUSB1761Bridge
BSCFLAGS=-keep-fires -cross-info -p +:$(LIBS)
SUFFIXES=
VERILOGDEST=../qsys_ip/USB1761Bridge
GENVERILOG=mkUSB1761Bridge.v
HW_TCL_A=USB1761Bridge_hw.tcl

all: $(VERILOGDEST) $(VERILOGDEST)/$(GENVERILOG) $(VERILOGDEST)/$(HW_TCL_A)

$(VERILOGDEST):
	mkdir $(VERILOGDEST)

$(VERILOGDEST)/$(GENVERILOG): $(BSVSRC) $(BSVINC)
	$(BSC) $(BSCFLAGS) -vdir $(VERILOGDEST) -u -verilog -g $(BSVTOP) $(BSVSRC)

$(VERILOGDEST)/$(HW_TCL_A): $(HW_TCL_A)
	cp $(HW_TCL_A) $(VERILOGDEST)

sim: $(BSVTST) $(BSVSRC) $(BSVINC)
	$(BSC) $(BSCFLAGS) -sim -g $(BSVTST_TOPMOD) -u $(BSVTST)
	$(BSC) $(BSCFLAGS) -sim -o $(BSVTST_TOPMOD) -e $(BSVTST_TOPMOD) $(BSVTST_TOPMOD).ba
	./$(BSVTST_TOPMOD) -m 1000000

.PHONY: clean
clean:
	rm -f  *~ *.bi *.bo *.ba *.info *.sched *.h *.o *.so *.cxx $(BSVTST_TOPMOD) $(GENVERILOG)
	rm -rf $(VERILOGDEST)
