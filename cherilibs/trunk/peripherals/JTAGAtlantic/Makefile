#!/usr/bin/make -f
#-
# Copyright (c) 2013 Simon W. Moore
# Copyright (c) 2016 A. Theodore Markettos
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
BSVSRC=ExampleCounter.bsv
BSVTOP=mkExampleCounter
BSVTST=$(BSVSRC)
BSVTST_TOPMOD=mkExampleCounter
# SWM: use aggressive conditions and add path to fine Avalon2ClientServer, etc.
BSCFLAGS=-keep-fires -cross-info -aggressive-conditions -p +:$(LIBS):../alterajtaguart
SUFFIXES=
VERILOGDEST=../qsys_ip/uart16550
GENVERILOG=mkAlteraJtagUartFIFO.v

all: $(VERILOGDEST) $(VERILOGDEST)/$(GENVERILOG) 

$(VERILOGDEST):
	mkdir $(VERILOGDEST)

$(VERILOGDEST)/$(GENVERILOG): $(BSVSRC) $(BSVINC)
	$(BSC) $(BSCFLAGS) -vdir $(VERILOGDEST) -u -verilog -g $(BSVTOP) $(BSVSRC)

sim: $(BSVTST) $(BSVSRC) $(BSVINC)
	$(BSC) $(BSCFLAGS) -sim -g $(BSVTST_TOPMOD) -u $(BSVTST)
	$(BSC) $(BSCFLAGS) -sim -o $(BSVTST_TOPMOD) -e $(BSVTST_TOPMOD) $(BSVTST_TOPMOD).ba
	./$(BSVTST_TOPMOD) -m 1000000

.PHONY: clean
clean:
	rm -f  *~ *.bi *.bo *.ba *.info *.sched *.h *.o *.so *.cxx $(BSVTST_TOPMOD) $(GENVERILOG)
	rm -rf $(VERILOGDEST)
