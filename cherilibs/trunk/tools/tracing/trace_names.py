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

import optparse, re, bisect

nm_re=re.compile('([0-9a-f]+) . (\w+)')
#trace_re=re.compile('DEBUG\: WB \[([0-9a-f]+) =>')
trace_re=re.compile('inst \d+ ([\da-f]+) : [\da-f]+')
def get_names(file_name):
    print "Parsing nm file..."
    nm_file = open(file_name, 'r')
    names=[]
    for line in nm_file:
        m=nm_re.match(line)
        if not m:
            sys.stderr.write("Warning: unrecognized line in nm file: ", line)
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
    names = get_names(options.nm_file)
    addresses=map(lambda x: x[0], names)
    syms = map(lambda x: x[1], names)
    trace_file=open(options.trace_file, 'r')
    for line in trace_file:
        m = trace_re.match(line)
        sym = ''
        if m:
            addr=int(m.group(1), 16)
            i = bisect.bisect_right(addresses, addr)-1
            sym = syms[i]
        print line[:-1], sym

if __name__=="__main__":
    parser = optparse.OptionParser()
    parser.add_option('-N','--nm', dest="nm_file", help="file containing symbol names (output of nm)")
    parser.add_option('-t','--trace', dest="trace_file", help="trace file to parse")
    (opts, args) = parser.parse_args()
    annotate_trace(opts)
