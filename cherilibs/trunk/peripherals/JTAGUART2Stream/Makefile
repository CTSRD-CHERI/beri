#!/usr/bin/make -f
#-
# Copyright (c) 2012-2013 Simon W. Moore
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
# SWM: use aggressive conditions and add path to fine Avalon2ClientServer, etc.
LIBS=../../
BSCFLAGS=-keep-fires -cross-info -aggressive-conditions -p +:$(LIBS)
SUFFIXES=
VERILOGDEST=../qsys_ip/JTAGUART2Stream

all: $(VERILOGDEST) $(VERILOGDEST)/mkUART2Stream.v $(VERILOGDEST)/UART2Stream_hw.tcl

$(VERILOGDEST):
	mkdir $(VERILOGDEST)

$(VERILOGDEST)/mkUART2Stream.v: UART2Stream.bsv
	$(BSC) $(BSCFLAGS) -vdir $(VERILOGDEST) -u -verilog -g mkUART2Stream UART2Stream.bsv

$(VERILOGDEST)/UART2Stream_hw.tcl: UART2Stream_hw.tcl
	cp UART2Stream_hw.tcl $(VERILOGDEST)

# SWM: remove *.c from "clean" since this will delete mtl_test_small.c
# that we want to keep
.PHONY: clean
clean:
	rm -f  *.bi *.bo *.ba *.info *.sched *.h *.o *.so $(VERILOGDEST)/mkUART2Stream.v $(VERILOGDEST)/UART2Stream_hw.tcl *~  >/dev/null
	rm -rf $(VERILOGDEST)
