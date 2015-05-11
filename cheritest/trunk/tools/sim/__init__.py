#-
# Copyright (c) 2011 Steven J. Murdoch
# Copyright (c) 2013 Alexandre Joannou
# Copyright (c) 2014 Jonathan Woodruff
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
from collections import defaultdict

## Mapping of register numbers and register names, used internally and by the
## predicate itself in generating error messages, etc.
MIPS_REG_NUM2NAME=[
  "zero", "at", "v0", "v1", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7",
  "t0", "t1", "t2", "t3", "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "t8",
  "t9", "k0", "k1", "gp", "sp", "fp", "ra"
]

## Inverse mapping of register name to register number
MIPS_REG_NAME2NUM={}
for num, name in enumerate(MIPS_REG_NUM2NAME):
    MIPS_REG_NAME2NUM[name] = num

## Regular expressions for parsing the log file
THREAD_RE=re.compile(r'======  Thread\s+([0-9]+)\s+======$')
MIPS_CORE_RE=re.compile(r'^DEBUG MIPS COREID\s+([0-9]+)$')
MIPS_REG_RE=re.compile(r'^DEBUG MIPS REG\s+([0-9]+) (0x................)$')
MIPS_PC_RE=re.compile(r'^DEBUG MIPS PC (0x................)$')
CAPMIPS_CORE_RE=re.compile(r'^DEBUG CAP COREID\s+([0-9]+)$')
CAPMIPS_PC_RE = re.compile(r'^DEBUG CAP PCC u:(.) perms:(0x.{8}) ' +
                            r'type:(0x.{6}) offset:(0x.{16}) base:(0x.{16}) length:(0x.{16})$')
CAPMIPS_REG_RE = re.compile(r'^DEBUG CAP REG\s+([0-9]+) u:(.) perms:(0x.{8}) ' +
                            r'type:(0x.{6}) offset:(0x.{16}) base:(0x.{16}) length:(0x.{16})$')

class MipsException(Exception):
    pass

class Capability(object):
    def __init__(self, u, perms, ctype, offset, base, length):
        self.u = int(u)
        self.ctype = int(ctype, 16)
        self.perms = int(perms, 16)
        self.offset = int(offset, 16)
        self.base = int(base, 16)
        self.length = int(length, 16)

    def __repr__(self):
        return 'u:%x perms:0x%08x type:0x%06x offset:0x%016x base:0x%016x length:0x%016x'%(
            self.u, self.perms, self.ctype, self.offset, self.base, self.length)

class ThreadStatus(object):
    '''Data object representing status of a thread (including cp2 registers if present)'''
    def __init__(self):
        self.reg_vals=[None] * len(MIPS_REG_NUM2NAME)
        self.pc=None
        self.cp2 = [None] * 32
        self.pcc = None

    def __getattr__(self, key):
        '''Return a register value by name'''
        if key.startswith("c"):
            regnum = int(key[1:])
            return self.cp2[regnum]
        else:
            reg_num = MIPS_REG_NAME2NUM.get(key, None)
            if reg_num is None:
                raise MipsException("Not a valid register name", key)
            return self.reg_vals[reg_num]

    def __getitem__(self, key):
        '''Return a register value by number'''
        if not type(key) is int or key < 0 or key > len(MIPS_REG_NUM2NAME):
            raise MipsException("Not a valid register number", key)
        return self.reg_vals[key]

    def __repr__(self):
        v = []
        for i in range(len(self.reg_vals)):
            v.append("%3d: 0x%016x"%(i, self.reg_vals[i]))
        v.append(" PC: 0x%016x"%(self.pc))
        v.append('')
        for i in range(len(self.cp2)):
            reg_num = ("c%d"%i).rjust(3)
            v.append("%s: %s"%(reg_num, self.cp2[i]))
        v.append("PCC: %s"%(self.pcc))
        return "\n".join(v)

class MipsStatus(object):
    '''Represents the status of the MIPS CPU registers, populated by parsing
    a log file. If x is a MipsStatus object, registers can be accessed by name
    as x.<REGISTER_NAME> or number as x[<REGISTER_NUMBER>].'''
    def __init__(self, fh):
        self.fh = fh
        self.threads=defaultdict(ThreadStatus)
        self.parse_log()
        if not len(self.threads):
            raise MipsException("No reg dump found in %s"%self.fh)
        if self.pc is None:
            raise MipsException("Failed to parse PC from %s"%self.fh)
        for i in range(len(MIPS_REG_NUM2NAME)):
            if self.reg_vals[i] is None:
                raise MipsException("Failed to parse register %d from %s"%(i,self.fh))

    def parse_log(self):
        '''Parse a log file and populate self.reg_vals and self.pc'''
        thread = 0
        for line in self.fh:
            line = line.strip()
            thread_groups = THREAD_RE.search(line)
            core_groups = MIPS_CORE_RE.search(line)
            reg_groups = MIPS_REG_RE.search(line)
            pc_groups = MIPS_PC_RE.search(line)
            cap_core_groups = CAPMIPS_CORE_RE.search(line)
            cap_reg_groups = CAPMIPS_REG_RE.search(line)
            cap_pc_groups = CAPMIPS_PC_RE.search(line)
            if (thread_groups):
                thread = int(thread_groups.group(1))
            # We use 'thread' for both thread id and core id.
            # This will need fixing if we ever have a CPU with both
            # multiple threads and multiple cores.
            if (core_groups):
                thread = int(core_groups.group(1))
            if (cap_core_groups):
                thread = int(cap_core_groups.group(1))
            if (reg_groups):
                reg_num = int(reg_groups.group(1))
                reg_val = int(reg_groups.group(2), 16)
                t = self.threads[thread]
                t.reg_vals[reg_num] = reg_val
            if (pc_groups):
                reg_val = int(pc_groups.group(1), 16)
                t = self.threads[thread]
                t.pc = reg_val
            if (cap_reg_groups):
                cap_reg_num = int(cap_reg_groups.group(1))
                t = self.threads[thread]
                t.cp2[cap_reg_num] = Capability(*cap_reg_groups.groups()[1:7])
            if (cap_pc_groups):
                t = self.threads[thread]
                t.pcc = Capability(*cap_pc_groups.groups()[0:6])

    def __getattr__(self, key):
        '''Return a register value by name. For backwards compatibility this defaults to thread zero.'''
        return getattr(self.threads[0], key)

    def __getitem__(self, key):
        '''Return a register value by number. For backwards compatibility this defaults to thread zero.'''
        return self.threads[0][key]

    def __repr__(self):
        v = []
        for i,t in self.threads.iteritems():
            v.append("======  Thread %3d  ======" % i)
            v.append(t.__repr__())
        return "\n".join(v)

MIPS_ICACHE_TAG_RE=re.compile(r'^DEBUG ICACHE TAG ENTRY\s*([0-9]+) Valid=([01]) Tag value=([0-9a-fA-F]+)$')

class ICacheException(Exception):
    pass

class ICacheTag(object):
    def __init__(self, index, valid, value):
        self.index = int(index)
        self.valid = (valid == '1')
        self.value = int(value,16)

    def __repr__(self):
        return 'idx:%3d valid:%r value:0x%x'%(self.index, self.valid, self.value)

class ICacheStatus(object):
    '''Represents the status of the Instruction Cache, populated by parsing
    a log file. If x is a ICacheStatus object, tags can be accessed by name
    as x.[TAG_INDEX].'''
    def __init__(self, fh):
        self.fh = fh
        self.start_pos = self.fh.tell()
        self.icache_tags = [None] * 512
        self.parse_log()
        for i in range(512):
            if self.icache_tags[i] is None:
                raise ICacheException("Failed to parse icache tag %d from %s"%(i,self.fh))

    def parse_log(self):
        '''Parse a log file and populate self.icache_tags'''
        for line in self.fh:
            line = line.strip()
            icache_groups = MIPS_ICACHE_TAG_RE.search(line)
            if (icache_groups):
                tag_idx = int(icache_groups.group(1))
                self.icache_tags[tag_idx] = ICacheTag(*icache_groups.groups()[0:3])

    def __getitem__(self, key):
        '''Return a tag by index'''
        if not type(key) is int or key < 0 or key > 511:
            raise ICacheException("Not a valid tag index", key)
        return self.icache_tags[key]

    def __repr__(self):
        v = []
        for i in range(len(self.icache_tags)):
            v.append("%r\n"%(self.icache_tags[i]))
        return "\n".join(v)
