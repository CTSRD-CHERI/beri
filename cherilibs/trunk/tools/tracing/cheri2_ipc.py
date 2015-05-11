#!/usr/bin/env python

#-
# Copyright (c) 2014 Robert M. Norton
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

import sys,re
import collections
insts = 0l
cycles = 0l
counter = collections.Counter()
cycles_re=re.compile(r'(\d+) dead cycles')

for line in sys.stdin.xreadlines():
    m=cycles_re.search(line)
    if m:
        insts += 1
        count = int(m.group(1))
        cycles += 1+count
        counter[count]+=1
    if insts & 0x3fff == 0:
        if cycles != 0:
            print chr(27) + "[2J"            
            print insts, cycles, float(cycles)/0x3fff
            #print counter.most_common()
            max_val = 0
            for cycs in xrange(50):
                val = cycs * counter[cycs]
                max_val = max(val,max_val)
            for cycs in xrange(50):
                print cycs,'#' * (120*cycs*counter[cycs]/max_val)
            counter = collections.Counter()
            cycles=0l
