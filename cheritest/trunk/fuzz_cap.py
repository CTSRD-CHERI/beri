#!/usr/bin/env python

#
# Copyright (c) 2015 Matthew Naylor
# Copyright (c) 2015 Alexandre Joannou
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

# Generate random capability-instruction sequences and check for
# equivalance between model (L3) and implementation (BSV).  This script
# must be run in the 'ctsrd/cheritest/trunk/' directory.  The other
# main assumptions are:
#
#  * a BSV-compiled CHERI is present at '../../cheri/trunk/sim'
#  * an L3-compiled CHERI is pointed to by the L3CHERI environment variable

# =======
# Imports
# =======

import subprocess
import os
import sys
import random
import uuid
import shutil
from optparse import OptionParser

# =======
# Globals
# =======

verbose = False

numTests = 10000

if 'L3CHERI' in os.environ.keys():
  L3CHERI = os.environ['L3CHERI']
else:
  print "Please set the L3CHERI environment variable"
  print "It should point to an L3-compiled binary"
  exit()

if 'BSVCHERI' in os.environ.keys():
  BSVCHERI = os.environ['BSVCHERI']
else:
  print "Please set the BSVCHERI environment variable"
  print "It should point to a bluespec simulator"
  exit()

# =====================
# MIPS64 register names
# =====================

regName = { '0' : '$zero'
          , '1' : '$at'
          , '2' : '$v0'
          , '3' : '$v1'
          , '4' : '$a0'
          , '5' : '$a1'
          , '6' : '$a2'
          , '7' : '$a3'
          , '8' : '$a4'
          , '9' : '$a5'
          , '10': '$a6'
          , '11': '$a7'
          , '12': '$t0'
          , '13': '$t1'
          , '14': '$t2'
          , '15': '$t3'
          , '16': '$s0'
          , '17': '$s1'
          , '18': '$s2'
          , '19': '$s3'
          , '20': '$s4'
          , '21': '$s5'
          , '22': '$s6'
          , '23': '$s7'
          , '24': '$t8'
          , '25': '$t9'
          , '26': '$k0'
          , '27': '$k1'
          , '28': '$gp'
          , '29': '$sp'
          , '30': '$fp'
          , '31': '$ra'
          }

# ==============
# Compile a test
# ==============

def compile():
  AS      = "mips64-as"
  LD      = "mips-linux-gnu-ld"
  OBJCOPY = "mips64-objcopy"
  OBJDUMP = "mips64-objdump"
  LDFLAGS = ["-EB", "-G0", "-T", "test_cached.ld", "-m", "elf64btsmip"]
  CFLAGS  = ["-EB", "-march=mips64", "-mabi=64", "-G0",
             "-ggdb", "-defsym", "TEST_CP2=1" ]
  MEMCONV = "../../cherilibs/trunk/tools/memConv.py"
  subprocess.call([AS] + CFLAGS  + ["-o", "obj/lib.o", "lib.s"])
  subprocess.call([AS] + CFLAGS  + ["-o", "obj/init.o", "init.s"])
  subprocess.call([AS] + CFLAGS  + ["-o", "obj/init_cached.o", "init_cached.s"])
  subprocess.call([AS] + CFLAGS  + ["-o", "obj/captest.o", "captest.s"])
  subprocess.call([LD] + LDFLAGS + ["-o", "obj/captest.elf", "obj/init.o", 
  																	"obj/init_cached.o", "obj/captest.o", 
  																	"obj/lib.o"])
  subprocess.call([OBJCOPY] + ["-S", "-O", "binary",
                               "obj/captest.elf", "obj/captest.bin"])
  subprocess.call(["python", MEMCONV, "-b", "obj/captest.bin"])
  subprocess.call(["cp", "mem64.hex", "../../cheri/trunk/"])

# ==========
# Run a test
# ==========

def run():
  # Obtain output from L3
  outputL3 = subprocess.check_output(
               [L3CHERI] + ["--uart-in", "/dev/null",
                           "--ignore", "HI", "--ignore", "LO",
                           "--format", "raw", "obj/captest.bin"])
  regFileL3 = {}
  for line in outputL3.split("\n"):
    fields = line.split()
    if fields != []:
      if fields[0] == "PC":
        regFileL3["PC"] = "0x" + fields[1].lower()
      if fields[0] == "Reg":
        regFileL3[fields[1]] = "0x" + fields[2].lower()

  # Obtain output from BSV
  outputBSV = subprocess.check_output([BSVCHERI, "+regDump"],
                                      stderr=subprocess.STDOUT)

  regFileBSV = {}
  for line in outputBSV.split("\n"):
    fields = line.split()
    if len(fields) >= 3:
      if fields[0] == "DEBUG" and fields[1] == "MIPS":
        if fields[2] == "PC":
          regFileBSV["PC"] = fields[3].lower()
        if fields[2] == "REG":
          regFileBSV[fields[3]] = fields[4].lower()

  failure = ""
  for k in regFileL3.keys():
    if regFileL3[k] != regFileBSV[k]:
      r = regName.get(k, k)
      failure = ( failure + "\n"
                + "Register " + r + " differs:\n"
                + "  model says: " + regFileL3[k] + "\n"
                + "  implementation says: " + regFileBSV[k] + "\n"
                )

  return failure

# =======================================
# Generate random capability instructions
# =======================================

def genDWord():
  x = random.choice(
    [ 0
    , 1
    , random.randrange(0, 65536)
    , random.randrange(0xffffffffffff0000, 0xffffffffffffffff)
    , random.randrange(0, 0xffffffffffffffff)
    ])
  return ("0x%x" % x)

def genCIncBase(c):
  return [ "  dli $t0, " + genDWord()
         , "  cincbase " + c + ", " + c + ", $t0"
         ]

def genCIncOffset(c):
  return [ "  dli $t0, " + genDWord()
         , "  cincoffset " + c + ", " + c + ", $t0"
         ]

def genCSetBounds(c):
  return [ "  dli $t0, " + genDWord()
         , "  csetbounds " + c + ", " + c + ", $t0"
         ]

def genCSetLen(c):
  return [ "  dli $t0, " + genDWord()
         , "  csetlen " + c + ", " + c + ", $t0"
         ]

def genCSetOffset(c):
  return [ "  dli $t0, " + genDWord()
         , "  csetoffset " + c + ", " + c + ", $t0"
         ]

def genCAndPerm(c):
  return [ "  dli $t0, " + genDWord()
         , "  candperm " + c + ", " + c + ", $t0"
         ]

def genCFromPtr(c):
  return [ "  dli $t0, " + genDWord()
         , "  cfromptr " + c + ", " + c + ", $t0"
         ]

def genCLC(c):
  return [ "  clc $c0, $0, 0($c10)"]
  
def genCSC(c):
  return [ "  csc $c0, $0, 0($c10)"]

def genCCheckPerm(c):
  return [ "  dli $t0, " + genDWord()
         , "  ccheckperm " + c + ", $t0"
         ]

def genCClearTag(c):
  return [ "  ccleartag " + c + ", " + c ]

def genCSet(c):
  return random.choice(
#      5 * [genCIncBase(c)]
      5 * [genCIncOffset(c)]
    + 5 * [genCSetBounds(c)]
    + 4 * [genCLC(c)]
    + 4 * [genCSC(c)]
    + 3 * [genCAndPerm(c)]
#    + 3 * [genCSetLen(c)]
    + 3 * [genCSetOffset(c)]
    + 2 * [genCFromPtr(c)]
    + 1 * [genCClearTag(c)]
    + 1 * [genCCheckPerm(c)]
    )

# ===============
# Generate a test
# ===============

# Pre test-sequence code
prelude = [
    "# Auto-generated by fuzz_cap.py"
  , ""
  , ".set mips64"
  , ".set noreorder"
  , ".set nobopt"
  , ".set noat"
  , ""
  , ".global test"
  , "test: .ent test"
  , "  daddu   $sp, $sp, -32"
  , "  sd      $ra, 24($sp)"
  , "  sd      $fp, 16($sp)"
  , "  daddu   $fp, $sp, 32"
  , ""
  , "  jal     bev_clear"
  , "  nop"
  , "  dli     $a0, 0xffffffff80000180"
  , "  dla     $a1, bev0_common_handler_stub"
  , "  dli     $a2, 12 # instruction count"
  , "  dsll    $a2, 2  # convert to byte count"
  , "  jal memcpy"
  , "  nop"
  , "  dli     $a0, 0    # set to 1 on exception"
  , "  dla     $t0, cap1 # address to load/store capability"
  , "  cfromptr     $c10, $c0, $t0 # $t0 # address to load/store capability"
  , "#  csc     $c10, $0, 0($c10) # store a valid capability there"
  , "  dli     $t0, 0"
  , ""
  , "# Auto-genetated test case:"
  ]

# Post test-sequence code
postlude = [
    "# End of autogenerated test case"
  , "  nop"
  , "  li $s7, 0xffff"
  , "skip:"
  , ""
  , "  mtc0      $zero, $26  # Dump registers"
  , "  mtc0      $zero, $23  # Terminate simulator"
  , "  nop"
  , "  .end test"
  , ""
  , ".ent bev0_handler"
  , "bev0_handler:"
  , "  li        $a0, 1"
  , "  cgetcause $a1"
  , "  dmfc0     $a2, $14    # EPC"
  , "  cgetbase  $a3, $c31   # EPCC"
  , "  mtc0      $zero, $26  # Dump registers"
  , "  mtc0      $zero, $23  # Terminate simulator"
  , "  nop"
  , "  .end bev0_handler"
  , ""
  , ".ent bev0_common_handler_stub"
  , "bev0_common_handler_stub:"
  , "  dla $k0, bev0_handler"
  , "  jr  $k0"
  , "  nop"
  , "  .end bev0_common_handler_stub"
  ]
  
# Random data section
def datasection(): return [
      " .data"
		, "	.align	5		# Must 256-bit align capabilities"
    , "cap1:		.dword	" + genDWord() + "	# uperms/reserved"
	  , "	.dword	" + genDWord() + "	# otype/eaddr"
	  , "	.dword	" + genDWord() + "	# base"
	  , "	.dword	" + genDWord() + "	# length"
  ]
    

# Returns True with probability 'p', and False otherwise
def chance(p):
  return random.random() < p

def queryCap():
  seq = []

  # Query resulting capability
  seq.extend(
    [ "  cgetperm   $s0, $c0"
    , "  cgetbase   $s1, $c0"
    , "  cgetlen    $s2, $c0"
    , "  cgetoffset $s3, $c0"
    , "  cgettag    $s4, $c0"
    , "  cgetsealed $s5, $c0"
    , "  cgettype   $s6, $c0"
    , "  cld        $t8, $0, 0($c10)"
    , "  cld        $t9, $0, 8($c10)"
    ])

  branch = random.choice(["cbts", "cbtu"])
  seq.append("  " + branch + " $c0, skip")

  return seq

# Generate a random capability (through a random sequence of
# capability-modification instructions), then read the fields of the
# resulting capability into general-purpose registers.

def testSetGet():
  testseq = []
  for i in range(0,random.randrange(3,8)):
    testseq.extend(genCSet("$c0"))

  # Print test sequence
  if verbose:
    for line in testseq:
      print line
    print

  # Query resulting capability
  seq = queryCap()
  testseq.extend(seq)

  return testseq

# Generate two random capabilities, then compare the capabilities
# using CPtrCmp variants.

def testCmp():
  testseq = []
  for i in range(0,random.randrange(1,4)):
    testseq.extend(genCSet("$c0"))
  testseq.append("")
  for i in range(0,random.randrange(1,4)):
    testseq.extend(genCSet("$c1"))
  testseq.append("")

  # Print test sequence
  if verbose:
    for line in testseq:
      print line
    print

  # Compare resulting capabilities
  testseq.extend(
    [ "  ceq    $s0, $c0, $c1"
    , "  cne    $s1, $c0, $c1"
    , "  clt    $s2, $c0, $c1"
    , "  cle    $s3, $c0, $c1"
    , "  cltu   $s4, $c0, $c1"
    , "  cleu   $s5, $c0, $c1"
    , "  ctoptr $s6, $c0, $c1"
    ])

  return testseq

# Generate three random capabilities. Seal the first capability using
# the second, then unseal the first using either the second or the
# third (randomly).

def testSealUnseal():
  testseq = []
  for i in range(0,random.randrange(1,4)):
    testseq.extend(genCSet("$c0"))
  testseq.append("")
  for i in range(0,random.randrange(1,4)):
    testseq.extend(genCSet("$c1"))
  testseq.append("")
  for i in range(0,random.randrange(1,4)):
    testseq.extend(genCSet("$c2"))
  testseq.append("")

  sealed = False
  if chance(0.75):
    # Seal c0 using c1
    testseq.append("  cseal $c0, $c0, $c1")
    sealed = True

  if not sealed or chance(0.5):
    # Unseal c0 using c1 or c2
    if chance(0.5):
      testseq.append("  cunseal $c0, $c0, $c1")
    else:
      testseq.append("  cunseal $c0, $c0, $c2")

  # Apply random capability modifications to c0
  if chance(0.75):
    for i in range(0,random.randrange(1,4)):
      testseq.extend(genCSet("$c0"))

  # Print test sequence
  if verbose:
    for line in testseq:
      print line
    print

  # Query resulting capability
  seq = queryCap()
  testseq.extend(seq)

  return testseq

# Write a test to a file
def emit(testseq, dataseq, filename="captest.s"):
  # Write to file "captest.s"
  f = open(filename, "w")
  for line in prelude + testseq + postlude + dataseq:
    f.write(line + "\n")
  f.close()

# Save a test
def save(testseq, dataseq, saveHex = False):
  # Ensure that "fuzz_cap" directory exists
  if not os.path.exists("fuzz_cap"):
    os.mkdir("fuzz_cap")

  # Create unique name
  filename = "fuzz_cap/t" + str(uuid.uuid1())

  # Write to disc
  print ("Saved to " + filename + ".s")
  emit(testseq, dataseq, filename + ".s")

  # Save hex file too if requested
  if saveHex:
    shutil.copyfile("mem64.hex", filename + ".hex");
    shutil.copyfile("obj/captest.bin", filename + ".bin");

# Generate a test
def gen():
  # Choose a test sequence
  testseq = []
  if chance(.33):
    if verbose: print "{Set-Get}"
    testseq = testSetGet()
  elif chance(0.33):
    if verbose: print "{PtrCmp}"
    testseq = testCmp()
  else:
    if verbose: print "{Seal-Unseal}"
    testseq = testSealUnseal()

  return testseq

# Shrink a failing test
def shrink(test, dataseq):
  n        = len(test)
  ommitted = []
  result   = []
  for omit in range(n):
    sys.stdout.write("\rShrinking (step %i/%i)" % (omit, n-1))
    sys.stdout.flush()
    new = []
    for (i, instr) in zip(range(n), test):
      if omit != i and i not in ommitted:
        new.append(instr)
    emit(new, dataseq)
    compile()
    failure = run()
    if failure != "":
      ommitted.append(omit)
      result = new
  print ""
  return result

# Generate, save, compile, and run a test.
# And then shrink the test if it fails.
def doOneTest():
  test = gen()
  dataseq = datasection()
  emit(test, dataseq)
  compile()
  failure = run()
  if failure != "":
    print " failed"
    shorter = shrink(test, dataseq)
    emit(shorter, dataseq)
    compile()
    save(shorter, dataseq, True)
    return False
  else:
    return True

# ====
# Main
# ====

try:
  random.seed()

  # Parse command line options
  parser = OptionParser()
  parser.add_option(
    "-r", "--run", dest="filename",
    help="replay test from FILE", metavar="FILE")
  parser.add_option(
    "-s", "--seed", dest="seed",
    help="use a specified random seed", metavar="SEED")
  (options, args) = parser.parse_args()

  if options.seed == None:
    random.seed()
    seed = random.randint(0, 100000)
  else:
    seed = int(options.seed)

  random.seed(seed)

  if options.filename == None:
    print ("Setting random seed to %i" % seed)
    for i in range (1,numTests):
      sys.stdout.write("\rTest %i/%i" % (i, numTests))
      sys.stdout.flush()
      doOneTest()
  else:
    print ("Replaying " + options.filename)
    shutil.copyfile(options.filename, "captest.s")
    compile()
    failure = run()
    if failure == "":
      print "Passed"
    else:
      print failure
except KeyboardInterrupt:
  print "\nBye!"
  exit()
