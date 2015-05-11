#!/usr/bin/make -f
#-
# Copyright (c) 2013 Philip Withnall
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
BSCFLAGS=-keep-fires -cross-info -aggressive-conditions -p +:$(LIBS):$(LIBS)/peripherals/PixelStream
SUFFIXES=
VERILOGDEST=../qsys_ip/AvalonSampler
GENVERILOG=$(VERILOGDEST)/mkAvalonSampler.v
HW_TCL=$(VERILOGDEST)/AvalonSampler_hw.tcl

all: $(VERILOGDEST) $(GENVERILOG) $(HW_TCL)

$(VERILOGDEST):
	mkdir $(VERILOGDEST)

$(VERILOGDEST)/mkAvalonSampler.v: AvalonSampler.bsv
	$(BSC) $(BSCFLAGS) -vdir $(VERILOGDEST) -u -verilog -g mkAvalonSampler AvalonSampler.bsv

$(VERILOGDEST)/AvalonSampler_hw.tcl: AvalonSampler_hw.tcl
	cp AvalonSampler_hw.tcl $(VERILOGDEST)

.PHONY: clean
clean:
	rm -f  *.bi *.bo *.ba *.info *.sched *.h *.o *.so $(GENVERILOG) $(HW_TCL) >/dev/null
	rm -rf $(VERILOGDEST)
