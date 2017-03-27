#!/usr/bin/python

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

# Run simulation, terminate when all threads finished, and emit trace

import sys
import subprocess
import re
import os

def main():
  inFile = open("testcase.trace", "r")
  outFile = open("trace.axe", "w")
  os.chdir("../..")
  p = subprocess.Popen(["./sim"],
         stderr=subprocess.PIPE, stdout=subprocess.PIPE)

  lines = []
  numFinished = 0
  while True:
    line = p.stderr.readline()
    if line == "": continue
    if line[0] != "!": continue
    if line[2:10] == "FINISHED":
      total = int(line[10:])
      numFinished = numFinished + 1
      if numFinished == total:
        break
    else:
      lines.append(line[1:])
  p.terminate()

  resps = []
  for i in range(0, numFinished):
    resps.append([])

  for line in lines:
    fields = line.split()
    resps[int(fields[0])].append(fields[1])

  for line in inFile:
    tid = int(line.split(":")[0])
    if "?" in line:
      resp = resps[tid].pop(0)
      line = line.replace("?", resp)
    outFile.write(line)

  outFile.close()

try:
  main()
except KeyboardInterrupt:
  sys.exit(-1)
