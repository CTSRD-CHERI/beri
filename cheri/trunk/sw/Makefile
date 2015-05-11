#-
# Copyright (c) 2013 Theo Markettos
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

# a stub makefile - if we make in this directory, make one of the children

CHERILIBS_DIR   = ../../../cherilibs/trunk
TOOLS_DIR       = $(CHERILIBS_DIR)/tools
INCLUDE_DIR     = $(CHERILIBS_DIR)/include

CC = mips-linux-gnu-gcc
AS = mips64-as
LD = mips-linux-gnu-ld
OBJCOPY = mips-linux-gnu-objcopy
OBJDUMP = mips64-objdump

clean:
	$(MAKE) -C hello-minilib clean
	$(MAKE) -C cheritest clean
	rm -f initial.hex

%:
	$(MAKE) -C hello-minilib $@
