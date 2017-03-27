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

# This script generates a random sequence of MIPS instructions (mostly
# loads, stores, syncs, RMWs) for each hardware thread.

import os
import sys
import random
import subprocess

# =============================================================================
# Initialisation
# =============================================================================

# Command-line usage
def usage():
  print "Usage: gen.py"
  print ""
  print "  Environment variables:"
  print "    * SEED"
  print "    * DEPTH"
  print "    * NUM_THREADS"
  print "    * NUM_ADDRS"
  print "    * MAX_DELAY"
  print "    * ASSOC"

# Read options
try:
  seed          = int(os.environ.get("SEED", "0"))
  depth         = int(os.environ.get("DEPTH", "100"))
  numThreads    = int(os.environ.get("NUM_THREADS", "2"))
  numAddrs      = int(os.environ.get("NUM_ADDRS", "3"))
  maxDelay      = int(os.environ.get("MAX_DELAY", "8"))
  assoc         = int(os.environ.get("ASSOC", "4"))
except:
  print "Invalid options"
  usage()
  sys.exit()

# Set random seed
random.seed(seed)

# Generate addresses
addrSet = []
for i in range(0, numAddrs):
  offset = random.randint(0, 65536)
  addrSet.append(offset)

# Generate extra addresses (for extra traffic & aliasing)
extraAddrSet = []
for a in addrSet:
  for i in range(0, 2):
    offset = random.randint(0, 4)
    extraAddrSet.append(a + offset)
  offset = random.randint(0, 200)
  for j in range(0, assoc+1):
    extraAddrSet.append(offset + j*1024)
for i in range(0, 8):
  offset = random.randint(0, 65536)
  extraAddrSet.append(offset)

# =============================================================================
# Globals
# =============================================================================

uniqueVal = 1;

# Distrubution of operations
opDist = ['S']*5 + ['L']*8 + ['SYNC']*3 + ['NOP']*3 
opDist = opDist + ['RMW']*3

# =============================================================================
# Functions
# =============================================================================

# Generate a random list of requests
def genReqs(t, cFile, traceFile):
  global uniqueVal
  cFile.write("case " + str(t) + ":\n")
  loads = 0
  for i in range(0, depth):
    op = random.choice(opDist);
    if random.randint(0, 1) == 0 or len(extraAddrSet) == 0:
      addr = random.choice(addrSet)
    else:
      addr = random.choice(extraAddrSet)
    addr = random.choice(addrSet)
    memLoc = "heap[" + str(addr) + "]"
    if op == 'L':
      cFile.write("log[" + str(loads) + "] = " + memLoc + ";\n")
      traceFile.write(str(t) + ": M[" + str(addr) + "] == ?\n")
      loads = loads + 1
    elif op == 'S':
      cFile.write(memLoc + " = " + str(uniqueVal) + ";\n")
      traceFile.write(str(t) + ": M[" + str(addr) + "] := ")
      traceFile.write(str(uniqueVal) + "\n")
      uniqueVal = uniqueVal+1
    elif op == 'SYNC':
      cFile.write("sync();\n")
      traceFile.write(str(t) + ": sync\n")
    elif op == 'NOP':
      cFile.write("nop();\n")
    elif op == 'RMW':
      cFile.write("log[" + str(loads) + "] = ")
      cFile.write("rmw(&" + memLoc + ", " + str(uniqueVal) + ");\n")
      traceFile.write(str(t) + ": { M[" + str(addr) + "] == ?; M[")
      traceFile.write(str(addr) + "] := " + str(uniqueVal) + " }\n")
      uniqueVal = uniqueVal+1
      loads = loads+1
  #for i in range(0, loads):
  #  cFile.write("emit(log[" + str(i) + "]);\n")
  cFile.write("for (int i = 0; i < " + str(loads) + "; i++) ")
  cFile.write("  emit(log[i]);\n")
  cFile.write("break;\n")

# =============================================================================
# Functions
# =============================================================================

cFile = open("testcase.c", "w")
traceFile = open("testcase.trace", "w")

cFile.write('#include "macros.h"\n')
for t in range(0, numThreads):
  genReqs(t, cFile, traceFile)

cFile.close()
traceFile.close()
