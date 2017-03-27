#!/usr/bin/env python
#-
# Copyright (c) 2012 Robert M. Norton
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
# Description: Tool to append the symbol name to lines of a cheri2 trace.
#
#*****************************************************************************/

import optparse, re, bisect, sys, subprocess

nm_re=re.compile('([0-9a-f]+) . (\w+)')

trace_res = {
# XXX update for cheri1
#'cheri1' : re.compile('inst \d+ ([\da-f]+) : [\da-f]+'),
#<instID>   T<Thread>: [<PC>] <result> inst=<encoding> (<n> dead cycles)
# result is '<reg><-<val>' or 'store' or 'branch/coproc'
#0       T0: [9000000040000000] fp<-0000000000000000 inst=3c1e0000 (0 dead cycles)
'cheri2' : re.compile('(?P<instID>\d+)\s+T(?P<thread>\d+): \[(?P<pc>[0-9a-f]+)\][^i]*inst=(?P<inst>[0-9a-f]+)'),
    'stream' : re.compile('^Time=\s+(?P<time>\d+) : (?P<pc>[0-9a-f]+): (?P<inst>[0-9a-f]+)\s+(?P<op>\w*)\s+(?P<args>[^D]*)DestReg <- 0x(?P<result>[0-9a-f]+) \{(?P<asid>[0-9a-f]+)}'),
    'raw': re.compile('(?P<pc>[0-9a-f]{16})'),
}

def usage(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)

def disassemble(inst):
    pass

def get_names(options):
    if options.exe_file:
        p = subprocess.Popen(['nm',options.exe_file],stdout=subprocess.PIPE)
        nm_file = p.stdout
    elif options.nm_file:
        nm_file = open(options.nm_file, 'r')
    else:
        usage("Error: please provide either exe file or nm output.")
    print "Parsing nm file..."
    names=[]
    for line in nm_file:
        m=nm_re.match(line)
        if not m:
            sys.stderr.write("Warning: unrecognized line in nm file: " + line)
            continue
        names.append((int(m.group(1), 16), m.group(2)))
    # Sort by address
    names.sort(cmp=lambda x, y: cmp(x[0],y[0]))
    # Got the data, now merge duplicate symbols into one.
    print "Removing duplicate symbols..."
    unique_names=[]
    prev_addr, prev_name=0, 'null'
    for (addr, name) in names:
        if addr != prev_addr:
            unique_names.append((prev_addr, prev_name))
            prev_name = name
            prev_addr = addr
        else:
            prev_name = prev_name + '/' + name
    unique_names.append((prev_addr, prev_name))
    print "Loaded names."
    return unique_names

def annotate_trace(options):
    names = get_names(options)
    addresses=map(lambda x: x[0], names)
    syms = map(lambda x: x[1], names)
    is_cheri2 = options.trace_format == 'cheri2'
    is_stream = options.trace_format == 'stream'
    is_raw    = options.trace_format == 'raw'
    trace_re = trace_res[options.trace_format]
    if options.trace_file is None:
        trace_file=sys.stdin
    else:
        trace_file=open(options.trace_file, 'r')
    for line in trace_file:
        m = trace_re.search(line)
        if m:
            addr=int(m.group('pc'), 16)
            i = bisect.bisect_right(addresses, addr)-1
            sym = syms[i]
            #inst = disassemble(m.group('inst'))
            if is_cheri2 or is_raw:
                print line[:-1], sym
            elif is_stream:
                print "%s %-6.6s %-25.25s result=%s asid=%s" % (m.group('pc'), m.group('op'), m.group('args').replace("\t",' '), m.group('result'), m.group('asid')), sym
        else:
            print line[:-1]

if __name__=="__main__":
    parser = optparse.OptionParser()
    parser.add_option('-e','--exe', dest="exe_file", help="Elf file containing symbol names")
    parser.add_option('-N','--nm', dest="nm_file", help="File containing output by nm (alternative to elf file)")
    parser.add_option('-t','--trace', dest="trace_file", help="Trace file to parse", default=None)
    parser.add_option('-f','--format', dest="trace_format", help="Format of trace file (cheri2, stream)", default='cheri2')
    (opts, args) = parser.parse_args()
    annotate_trace(opts)
