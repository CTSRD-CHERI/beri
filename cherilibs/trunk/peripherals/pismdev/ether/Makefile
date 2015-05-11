#
# Copyright (c) 2011 Wojciech A. Koszek
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
CFLAGS+=	-g -ggdb -Wall -pedantic -O0
CFLAGS+=	-std=c99

BSVFLAGS=	-D CHERI_NET_TEST -simdir ./bsim -bdir ./bsim -sim -p +:..:../.. -u
BSVFILES=	\
	EtherCAP.bsv

all:	test a.out

a.out:	EtherCAP.bsv ethercap.c makefile
	mkdir -p -m 0755 bsim
	bsc $(BSVFLAGS) -g mkTestBench $(BSVFILES)
	bsc $(BSVFLAGS) -e mkTestBench -o a.out ./bsim/*.ba ethercap.c

test:	ethercap.c
	$(CC) $(CFLAGS) -DTEST -o test ethercap.c

clean:
	rm -rf bsim a.out a.out.so ethercap.o test
