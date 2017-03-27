#!/bin/bash

# Copyright 2016 Matthew Naylor
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream
# Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
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

PLATFORM="beri"
ARCH="-DARCH_MIPS"

CC="mips-linux-gnu-gcc"
AS="mips-linux-gnu-as"
LD="mips-linux-gnu-ld"
OBJCOPY="mips-linux-gnu-objcopy"
OBJDUMP="mips-linux-gnu-objdump"

OPT="-O2"
CFLAGS="-EB -march=mips64 -mabi=64 -G 0 -ggdb $OPT -I."
LDFLAGS="-EB -G 0 -T $PLATFORM/$PLATFORM.ld -m elf64btsmip"

CFILES="main mips/arch beri/platform"
OFILES=""
for F in $CFILES
do
  OFILES="$OFILES `basename $F.o`"
  $CC $CFLAGS -std=gnu99 -Wall $ARCH -c -o `basename $F.o` $F.c
done

$AS $CFLAGS -o entry.o beri/entry.s
$LD $LDFLAGS -o main.elf entry.o $OFILES
$OBJCOPY -S -O binary main.elf main.bin
