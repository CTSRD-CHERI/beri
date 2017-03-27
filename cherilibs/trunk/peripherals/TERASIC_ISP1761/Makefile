#-
# Copyright (c) 2012, 2013 Simon Moore
# Copyright (c) 2012 Jonathan Woodruff
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


VERILOGDEST=../qsys_ip/TERASIC_ISP1761
SRC=ISP1761_IF

all: $(VERILOGDEST)/$(SRC).v $(VERILOGDEST)/$(SRC)_hw.tcl

$(VERILOGDEST)/$(SRC).v: $(SRC).v $(VERILOGDEST)
	cp $(SRC).v $(VERILOGDEST)

$(VERILOGDEST)/$(SRC)_hw.tcl: $(SRC)_hw.tcl $(VERILOGDEST)
	cp $(SRC)_hw.tcl $(VERILOGDEST)

$(VERILOGDEST):
	mkdir $(VERILOGDEST)

clean:
	rm -rf $(VERILOGDEST)
