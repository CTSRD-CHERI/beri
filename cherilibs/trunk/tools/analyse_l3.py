#!/usr/bin/env python
#-
# Copyright (c) 2012-2016 Robert M. Norton
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
#*****************************************************************************
#
# Author: Robert M. Norton <robert.norton@cl.cam.ac.uk>
# 
#*****************************************************************************
#
# Description: Tool to append the symbol name to lines of an l3 trace.
#
#*****************************************************************************/

import optparse, bisect, sys, subprocess, struct, re, os, functools
from collections import defaultdict
import csv

nm_re=re.compile('([0-9a-f]+) (.) ([$\.\w]+)')
inst_re=re.compile('^instr (?P<core>\d) (?P<instno>\d+) (?P<PC>[0-9a-f]+) : (?P<opcode>[0-9a-f]+)\s+(?P<disas>.*)$')
vaddr_re=re.compile('vAddr\s+0x(?P<vaddr>[0-9a-f]+)')
def usage(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)

exception_vectors = (
    (0xFFFFFFFFBFC00280, "kernel/bev_TLBMiss"       ),
    (0xFFFFFFFFBFC00300, "kernel/bev_CacheErr"      ),
    (0xFFFFFFFFBFC00380, "kernel/bev_common"        ),
    (0xFFFFFFFFBFC00480, "kernel/bev_CP2Trap"       ),
    (0xFFFFFFFF80000080, "kernel/vec_TLBMiss"       ),
    (0xFFFFFFFF80000100, "kernel/vec_CacheErr"      ),
    (0xFFFFFFFF80000180, "kernel/vec_common"        ),
    (0xFFFFFFFF80000280, "kernel/vec_CP2Trap"       ),
)

def get_names_file(name, nm_file, quiet, addr):
    for line in nm_file:
        m=nm_re.match(line)
        if not m :
            if not quiet: sys.stderr.write("Warning: unrecognized line in nm file: " + line)
            continue
        if m.group(2) not in ('U', 'W'):
            yield (int(m.group(1), 16) + addr, "%s/%s" % (name, m.group(3)))

def get_names(options):
    names=[]
    for exe in options.elf:
        addr="0"
        if exe.find('@') != -1:
            (exe, addr) = exe.split('@')
        if not options.quiet:
            sys.stderr.write("Loading exe file %s\n" % exe)
        p = subprocess.Popen(['nm','--defined-only', exe],stdout=subprocess.PIPE)
        names.extend(get_names_file(exe, p.stdout, options.quiet, long(addr, 16)))
        p.wait()
    for nm in options.nm:
        if not options.quiet:
            sys.stderr.write("Parsing nm file %s\n" % options.nm_file)
        nm_file = open(options.nm_file, 'r')
        names.extend(get_names_file(nm, nm_file, options.quiet, 0))
    # Because the exception vectors are not labelled in the elf kernel's elf 
    # file we manually add symbols for them.
    names.extend(exception_vectors)
    # Sort by address
    names.sort(cmp=lambda x, y: cmp(x[0],y[0]))
    # Got the data, now merge duplicate symbols into one.
    if not options.quiet: sys.stderr.write("Merging duplicate symbols\n")
    unique_names=[]
    prev_addr, prev_name=0, 'null'
    for (addr, name) in names:
        if addr != prev_addr:
            unique_names.append((prev_addr, prev_name))
            prev_name = name
            prev_addr = addr
        else:
            prev_name = prev_name + '|' + name
    unique_names.append((prev_addr, prev_name))
    return unique_names

def get_sym(addresses, syms, addr):
    i = bisect.bisect_right(addresses, addr)-1
    sym = syms[i]
    sym_addr = addresses[i]
    sym_off  = addr - sym_addr
    return (sym, sym_off)


def annotate_trace(file_name, options):
    names = get_names(options)
    addresses=map(lambda x: x[0], names)
    syms = map(lambda x: x[1], names)

    if file_name is None:
        trace_file=sys.stdin
    else:
        trace_file = open(file_name, 'r')
    for line in trace_file:
        inst_match = inst_re.match(line)
        if inst_match:
            pc = long(inst_match.group('PC'), 16)
            sym, sym_off = get_sym(addresses, syms, pc)
            print "%-80s %s+0x%x" % (inst_match.group(0), sym, sym_off)
        else:
            vaddr_match = vaddr_re.search(line)
            if vaddr_match:
                vaddr = long(vaddr_match.group('vaddr'), 16)
                sym, sym_off = get_sym(addresses, syms, vaddr)
                print line[:-1], "%s+0x%x" % (sym, sym_off)
            else:
                print line,

if __name__=="__main__":
    # patch optparse so that it does not reformat our epilogue
    optparse.OptionParser.format_epilog = lambda self, formatter: self.epilog
    parser = optparse.OptionParser("%prog [options] TRACE...")
    parser.add_option('--elf',        default=[], action='append', help="Elf file(s) containing symbol names")
    parser.add_option('--nm',         default=[], action='append', help="File(s) containing output by nm (alternative to elf file)")
    parser.add_option('--verbose',    default=True, dest='quiet', action='store_false', help="Be verbose.")
    (opts, args) = parser.parse_args()
    if not args:
        annotate_trace(None, opts)
    for file_name in args:
        annotate_trace(file_name, opts)
