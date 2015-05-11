#-
# Copyright (c) 2011 Steven J. Murdoch
# Copyright (c) 2011 William M. Morland
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

import re

## Mapping of register numbers and register names, used internally and by the
## predicate itself in generating error messages, etc.
MIPS_REG_NUM2NAME=[
  "zero", "at", "v0", "v1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
  "t0", "t1", "t2", "t3", "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "t8",
  "t9", "k0", "k1", "gp", "sp", "fp", "ra"
]

## WILL: Issue in that rather than a0-a7 & t0-t3 we have in GXemul a0-a3 & t0-t7
## although t0-t3 appears to map to a4-a7y. This is indicative of the old O32
## ABI rather than the newer N32/N64 ABI we are using. Despite this it seems as
## though even when explicitly emulating N64 CPUs it maintains the O32
## naming conventions for the registers.


## Inverse mapping of register name to register number
MIPS_REG_NAME2NUM={}
for num, name in enumerate(MIPS_REG_NUM2NAME):
    MIPS_REG_NAME2NUM[name] = num

## Regular expressions for parsing the log file
MIPS_REG_RE=re.compile(r'\b(?!pc)(?!hi)(?!lo)(..) = (0x................)')
MIPS_PC_RE=re.compile(r'\bpc = (0x................)')

class MipsException(Exception):
    pass

class MipsStatus(object):
    '''Represents the status of the MIPS CPU registers, populated by parsing
    a log file. If x is a MipsStatus object, registers can be accessed by name
    as x.<REGISTER_NAME> or number as x[<REGISTER_NUMBER>].'''
    def __init__(self, fh):
        self.reg_vals = [None] * len(MIPS_REG_NUM2NAME)
        self.pc = None
        self.parse_log(fh)
	self.reg_vals[0] = 0
        if self.pc is None:
            raise MipsException("Failed to parse PC from %s"%fh)
        for i in range(len(MIPS_REG_NUM2NAME)):
            if self.reg_vals[i] is None:
                raise MipsException("Failed to parse register %d from %s"%(i,fh))


    def parse_log(self, fh):
        '''Parse a log file and populate self.reg_vals and self.pc'''
        for line in fh:
            line = line.strip()
            reg_groups = MIPS_REG_RE.findall(line)
            pc_groups = MIPS_PC_RE.search(line)
            if (reg_groups):
		for reg in reg_groups:
		        reg_name = reg[0]
			if reg_name == 't0':
				reg_name = 'a4'
			elif reg_name == 't1':
				reg_name = 'a5'
			elif reg_name == 't2':
				reg_name = 'a6'
			elif reg_name == 't3':
				reg_name = 'a7'
			elif reg_name == 't4':
				reg_name = 't0'
			elif reg_name == 't5':
				reg_name = 't1'
			elif reg_name == 't6':
				reg_name = 't2'
			elif reg_name == 't7':
				reg_name = 't3'
		        reg_val = int(reg[1], 16)
			reg_num = MIPS_REG_NAME2NUM.get(reg_name, None)
		        self.reg_vals[reg_num] = reg_val
            if (pc_groups):
                reg_val = int(pc_groups.group(1), 16)
                self.pc = reg_val

    def __getattr__(self, key):
        '''Return a register value by name'''
        reg_num = MIPS_REG_NAME2NUM.get(key, None)
        if reg_num is None:
            raise MipsException("Not a valid register name", key)
        return self.reg_vals[reg_num]

    def __getitem__(self, key):
        '''Return a register value by number'''
        if not type(key) is int or key < 0 or key > len(MIPS_REG_NUM2NAME):
            raise MipsException("Not a valid register number", key)
        return self.reg_vals[key]
