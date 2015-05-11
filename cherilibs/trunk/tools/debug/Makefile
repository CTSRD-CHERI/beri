#-
# Copyright (c) 2011-2012 Robert N. M. Watson
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2012-2013 SRI International
# Copyright (c) 2012 Robert M. Norton
# Copyright (c) 2012-2013 Bjoern A. Zeeb
# Copyright (c) 2013 Jonathan Anderson
# Copyright (c) 2015 A. Theodore Markettos
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

all: cherictl 
#cherictl_test tests

ifdef PCIEXPRESS
DEFINES+= -D ENABLE_PCIEXPRESS
endif
ifdef JTAG_ATLANTIC
DEFINES+= -D JTAG_ATLANTIC
endif
ifdef BUFFERING
DEFINES+= -D ENABLE_STREAM_BUFFERING
endif

UNAME:= $(shell uname)


CFLAGS= -Wall -g -Werror -I . -I ../../include -I /usr/local/include $(DEFINES)
#CFLAGS+=-DBERI_NETFPGA -static
CC?=	gcc
CXX?=	g++
LIBS=	-L /usr/local/lib -lbz2
ifdef PCIEXPRESS
LIBS+= -lpciaccess
endif
ifdef JTAG_ATLANTIC
CFLAGS+=	-L$(QUARTUS_ROOTDIR)/linux64
LIBS+= -ljtag_atlantic -ljtag_client
CFLAGS+=	-I..
endif

PROGS:=	berictl		\
	cherictl	
#	cherictl_test

ifeq ($(UNAME), FreeBSD)
PROGS+= beri_terminal
endif

# this is really predicated on clang rather than OS X, but that's harder to test
ifeq ($(UNAME), Darwin)
CCFLAGS=-pthread
else
CCFLAGS=
LIBS+=	-pthread
endif

SRCS:=	altera_systemconsole	\
	cherictl_base		\
	cherictl_util		\
	cheri_debug		\
	cheri_atse		\
	cheri_err		\
	cheri_pic		\
	cheri_systemconsole	\
	eav			\
	macosx			\
	mips_decode		\
	status_bar		\
	which
	
ifeq ($(UNAME), FreeBSD)
SRCS+= sockit_stream
endif

ifdef PCIEXPRESS
SRCS+= pcie_stream
endif
ifdef BUFFERING
SRCS+= circular_buffer
endif

TESTEXTRAS=

ifeq ($(UNAME), Darwin)
CFLAGS+=-I tests/memorymapping/src
SRCS+=	tests/memorymapping/src/fmemopen
TESTEXTRAS+=tests/memorymapping/src/fmemopen.o
endif

TESTS:= \
	altera_systemconsole

ifdef JTAG_ATLANTIC
SRCS+= jtagatlantic
TESTS+= jtagatlantic
endif


OBJS:=		$(addsuffix .o,$(SRCS))
POBJS:=		$(addsuffix .o,$(PROGS))

%.o: %.c
	$(CC) -c $(CFLAGS) $(CCFLAGS) -o $@ $<
%.o: %.cc
	$(CXX) -c $(CFLAGS) $(CCFLAGS) -o $@ $<

ifeq ($(UNAME), FreeBSD)
all: berictl cherictl beri_terminal blk_ioctl
else
all: berictl cherictl
endif

berictl: berictl.o $(OBJS)
	$(CC) $(CFLAGS) -o berictl $^ $(LIBS)

cherictl: cherictl.o $(OBJS)
	$(CC) $(CFLAGS) -o cherictl $^ $(LIBS)

cherictl_test: cherictl_test.o $(OBJS)
	$(CC) $(CFLAGS) -o cherictl_test $^ $(LIBS)

cherictl.static: cherictl.o $(OBJS)
	$(CC) $(CFLAGS) -static -o cherictl.static $^ $(LIBS)

beri_terminal: beri_terminal.o $(OBJS)
	$(CC) $(CFLAGS) -o beri_terminal $^ $(LIBS)

blk_ioctl: blk_ioctl.o $(OBJS)
	$(CC) $(CFLAGS) -o blk_ioctl $^ $(LIBS)

clean:
	rm -f berictl cherictl cherictl_test \
		beri_terminal blk_ioctl \
		$(OBJS) $(POBJS) \
		tests/*.o tests/alltests

test: tests
	./tests/alltests

tests: tests/alltests

tests/alltests: tests/CuTest.o \
	$(patsubst %,tests/%.o,$(TESTS)) \
	$(patsubst %,%.o,$(TESTS)) \
	cheri_err.o \
	tests/alltests.o \
	$(TESTEXTRAS)
	$(CC) $(CFLAGS) -o $@ $^ $(LIBS) 
