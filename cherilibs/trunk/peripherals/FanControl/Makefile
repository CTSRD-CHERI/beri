#!/usr/bin/make -f
#-
# Copyright (c) 2012-2013 Simon W. Moore
# Copyright (c) 2014 A. Theodore Markettos
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
BSCFLAGS=-keep-fires -cross-info -aggressive-conditions -p +:$(LIBS)
SUFFIXES=
VERILOGDEST=../qsys_ip/FanControl
GENVERILOG=$(VERILOGDEST)/mkFanControl50MHz.v
HW_TCL=$(VERILOGDEST)/FanControl50MHz_hw.tcl
EXTRA=$(VERILOGDEST)/temp_sense.v

all: $(VERILOGDEST) $(GENVERILOG) $(HW_TCL) $(EXTRA)

$(VERILOGDEST):
	mkdir $(VERILOGDEST)

$(VERILOGDEST)/mkFanControl50MHz.v: FanControl.bsv
	$(BSC) $(BSCFLAGS) -vdir $(VERILOGDEST) -u -verilog -g mkFanControl50MHz FanControl.bsv

$(VERILOGDEST)/FanControl50MHz_hw.tcl: FanControl50MHz_hw.tcl
	cp FanControl50MHz_hw.tcl $(VERILOGDEST)

$(VERILOGDEST)/temp_sense.v: megawizard
	cp temp_sense.v $(VERILOGDEST)

.PHONY:	megawizard

megawizard:
	cp temp_sense.v.template temp_sense.v
	qmegawiz -silent module=alttemp_sense temp_sense.v

.PHONY: clean
clean:
	rm -f  *.bi *.bo *.ba *.info *.sched *.h *.o *.so $(GENVERILOG) $(HW_TCL) $(EXTRA) >/dev/null
	rm -f  *.v > /dev/null
	rm -rf $(VERILOGDEST)
