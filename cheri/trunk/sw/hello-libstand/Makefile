#
# Copyright (c) 2014 Michael Roe
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

#
# Build a 'hello world' program that runs on bare-metal CHERI, using
# FreeBSD's libstand.a,  a library for stand-alone (no operating system)
# applications.
#
# This Makefile is intended to be run on FreeBSD (not Linux).
#

CC=$(CHERI_SDK)/bin/clang
CFLAGS=--sysroot=$(CHERI_SDK) -target cheri-unknown-freebsd

AS=$(CHERI_SDK)/bin/as
AFLAGS=-EB -march=mips64 -mabi=64

LD=$(CHERI_SDK)/bin/ld
LDFLAGS=-EB -G0 -melf64btsmip_fbsd --no-warn-mismatch
# We need to pass -no-warn-mismatch to the linker because clang's built-in
# assembler doesn't support the .set mips64 directive. Without .set mips64,
# the linker can't tell that the object files are MIPS64, and will incorrectly
# think that we're attempting to mix MIPS64 and MIPS32 object files.

OBJCOPY=$(CHERI_SDK)/bin/objcopy

.SUFFIXES: .elf .mem .hex

.c.o:
	$(CC) $(CFLAGS) -c $<

.s.o:
	$(AS) $(AFLAGS) -o $@ $<

.mem.hex:
	raw2ihex $< > $@

.elf.mem:
	$(OBJCOPY) -S -O binary $< $@

all: hello.mem

clean:
	 rm -f *.o hello.elf hello.mem

hello.elf: test.o cheri_io.o init.o lib.o prog_link.ld
	$(LD) $(LDFLAGS) -T prog_link.ld -o hello.elf lib.o cheri_io.o -L $(CHERI_SDK)/usr/lib -l stand

test_uart.elf: test_uart.o prog_link2.ld
	$(LD) $(LDFLAGS) -T prog_link2.ld -o test_uart.elf

init.s:
	echo "This is work in progress: init.s not written yet"

lib.s:
	echo "This is work in progress: lib.s. not written yet"
