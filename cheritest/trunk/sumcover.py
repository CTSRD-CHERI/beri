#!/usr/bin/env python

#
# Copyright (c) 2015 Matthew Naylor
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

# The L3 model can be compiled with coverage profiling enabled, e.g.
#
#   make l3mips_coverage
#
# When the resulting executable is run, it will emit a file
# 'mlmon.out' containing coverage information in binary form.  To
# convert this into a human-readable form, we can type:
#
#   mlprof -raw true -show-line true l3mips_coverage mlmon.out > out.cover
#
# The purpose of this script is to take a set of .cover files, e.g.
# one for each test in the test suite, and merge them into a single
# .cover file by summing the counts for each branch, e.g.
#
#   sumcover.py *.cover > all.cover

import sys

hist = {}
filenames = sys.argv[1:]

for filename in filenames:
  with open(filename) as f:
    lines = f.readlines()
  for line in lines[3:]:
    words = line.split()
    key = " ".join(words[0:-2])
    val = words[-1].translate(None, '(,)')
    hist[key] = hist.get(key, 0) + int(val)

for w in sorted(hist, key=hist.get, reverse=True):
  print hist[w], w
