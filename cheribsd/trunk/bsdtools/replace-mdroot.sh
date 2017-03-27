#!/bin/bash
#-
# Copyright (c) 2016 A. Theodore Markettos
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


# A simple script to replace the mdroot in a kernel image with a new file

# Syntax: replace-mdroot.sh <old kernel image> <mdroot> <new kernel image>

# based on:
# https://lists.freebsd.org/pipermail/freebsd-mips/2011-February/001400.html

OLDKERNEL=$1
MDROOT=$2
NEWKERNEL=$3

if [ $# -ne 3 ] ; then
	echo "Syntax: replace-mdroot.sh <old kernel image> <mdroot> <new kernel image>"
	exit 1
fi	

addr=($(strings -td $OLDKERNEL | grep "MFS Filesystem" | awk '{print $1}'))
rootfs_start=${addr[0]} 
rootfs_end=$((${addr[1]}+1)) 
rootfs_hole_length=$(( $rootfs_end - $rootfs_start - 1 ))
rootfs_length=$(wc -c < $MDROOT)

if [ $rootfs_length -ne $rootfs_hole_length ] ; then
	echo "Trying to insert mdroot of length $rootfs_length bytes, but hole in kernel is $rootfs_hole_length bytes"
	exit 2
fi

echo "Inserting kernel image from $rootfs_start to $rootfs_end" 
head -c ${rootfs_start} $OLDKERNEL > $NEWKERNEL
cat $MDROOT >> $NEWKERNEL
tail -c +${rootfs_end} $OLDKERNEL >> $NEWKERNEL
#bzip2 $NEWKERNEL
