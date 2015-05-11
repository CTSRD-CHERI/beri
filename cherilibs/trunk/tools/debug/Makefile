#-
# Copyright (c) 2011-2012 Robert N. M. Watson
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2012-2013 SRI International
# Copyright (c) 2012 Robert M. Norton
# Copyright (c) 2012-2013 Bjoern Z. Zeeb
# Copyright (c) 2013 Jonathan Anderson
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

all: cherictl cherictl_test tests

CFLAGS=	-Wall -g -Werror -I . -I ../../include
#CFLAGS+=-DBERI_NETFPGA -static
CC?=	gcc

PROGS:=	berictl		\
	cherictl	\
	cherictl_test

SRCS:=	altera_systemconsole	\
	cherictl_base		\
	cherictl_util		\
	cheri_debug		\
	cheri_atse		\
	cheri_err		\
	cheri_pic		\
	cheri_systemconsole	\
	eav			\
	mips_decode		\
	status_bar		\
	which

TESTS:= \
	altera_systemconsole

OBJS:=	$(addsuffix .o,$(SRCS))
POBJS:=	$(addsuffix .o,$(PROGS))

%.o: %.c
	$(CC) -c $(CFLAGS) -o $@ $<

all: berictl cherictl

berictl: berictl.o $(OBJS)
	$(CC) $(CFLAGS) -o berictl $^ -lbz2

cherictl: cherictl.o $(OBJS)
	$(CC) $(CFLAGS) -o cherictl $^ -lbz2

cherictl_test: cherictl_test.o $(OBJS)
	$(CC) $(CFLAGS) -o cherictl_test $^ -lbz2

cherictl.static: cherictl.o $(OBJS)
	$(CC) $(CFLAGS) -static -o cherictl.static $^ -lbz2

clean:
	rm -f berictl cherictl cherictl_test $(OBJS) $(POBJS) \
	tests/*.o tests/alltests

test: tests
	./tests/alltests

tests: tests/alltests

tests/alltests: tests/CuTest.o \
	$(patsubst %,tests/%.o,$(TESTS)) \
	altera_systemconsole.o \
	cheri_err.o
