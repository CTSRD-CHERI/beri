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
# Description: Tool which attempts to find TLB bugs by parsing the output of
#              of a cheri2 trace and comparing against a python model.
#
#*****************************************************************************/

import sys, re, struct

ignore_list=[
    0x7f000000, # uart0
    0x7f001000, # uart1
    0x7f002000, # uart2
    0x7f008230, # sdcard
    0x7f008210, # sdcard
    0x7f008218, # sdcard
    0x4154f0,   # harmless ssnop following eret
    ]

def getFullMask(m):
    byte = 0xffL
    ret = 0L
    while m:
        if m & 1:
            ret += byte
        byte = byte << 8
        m = m >> 1
    return ret

class Exception(object):
    def __init__(self, code, sym, badAddr):
        self.code = code
        self.sym = sym
        self.badAddr = badAddr

class Instr(object):
    def __init__(self):
        self.exp = None
        self.dmem = None
        self.pc = None
        self.inst_no = None
        self.enc = None

class TLBEntryHi(object):
    def __init__(self, r, vpn2, valid, mask, g, asid):
        self.r = r
        self.vpn2 = vpn2
        self.g = g
        self.asid = asid
        self.mask = mask
        self.valid = valid # not really needed
        if mask != 0:
            raise Exception("non-zero mask not supported")
        self.matchval = (r << 62) | (vpn2 << 13) | (0 if g else asid)
    def __eq__(self, other):
        return self.r == other.r and self.vpn2 == other.vpn2 and self.g == other.g and self.asid == other.asid and self.mask == other.mask and self.valid == other.valid

    def __str__(self):
        return "TLbEntryHi: r=%x vpn2=%x asid=%x g=%s valid=%s mask=%x" % (self.r, self.vpn2, self.asid, self.g, self.valid, self.mask)

    def matches(self, asid, va):
        return self.matchval == (va & 0xffffffffffffe000) | (0 if self.g else asid)
    def get_va(self):
        return (self.r << 62) | (self.vpn2 << 13)

class TLBEntryLo(object):
    def __init__(self, pfn, cache, dirty, valid, g):
        self.pfn   = pfn
        self.cache = cache
        self.dirty = dirty
        self.valid = valid
        self.g     = g
    def __eq__(self, other):
        return self.pfn == other.pfn and self.cache == other.cache and self.dirty == other.dirty and self.valid == other.valid and self.g == other.g
    def __str__(self):
        return "TLbEntryLo: pfn=%x valid=%s dirty=%s g=%s cache=%s" % (self.pfn, self.valid, self.dirty, self.g, self.cache)

class TLBEntry(object):
    def __init__(self, hi, lo0, lo1):
        self.hi = hi
        self.lo0 = lo0
        self.lo1 = lo1

    def matches(self, asid, va):
        return self.hi.matches(asid, va)

    def __eq__(self, other):
        return self.hi == other.hi and self.lo0 == other.lo0 and self.lo1 == other.lo1

    def __str__(self):
        return "hi=%s lo0=%s lo1=%s" % (self.hi, self.lo0, self.lo1)

class TLB(object):
    def __init__(self):
        self.entries = [None] * 32
        self.cache = (None, None)

    def findMatch(self, asid, va):
        for idx, entry in enumerate(self.entries):
            if not entry: continue
            if entry.matches(asid, va):
                self.cache = (idx, entry)
                return (idx, entry)
        return (None, None)

    def lookup(self, asid, va, write):
        (idx, m) = self.findMatch(asid, va)
        if not m:
            return ("miss", None)
        lo = m.lo1 if (va & 0x1000) else m.lo0
        if not lo.valid:
            return ("invalid", None)
        if write and not lo.dirty:
            return ("readonly", None)
        else:
            return (None, (lo.pfn << 12) | (va & 0xfff))

class CP0(object):
    def __init__(self):
        hi  = TLBEntryHi(0, 0, False, 0, False, 0)
        lo0 = TLBEntryLo(0, 0, False, False, False)
        lo1 = TLBEntryLo(0, 0, False, False, False)
        self.tlbEntry = TLBEntry(hi, lo0, lo1)
        self.index = 0
        self.llAddr = None

class Mem(dict):
    def __init__(self, *arg, **kw):
        super(Mem, self).__init__(*arg, **kw)
        self.map_file("kernel", 0x100000)
        self.map_file("mem.bin", 0x40000000)

        
    def map_file(mem, path, addr):
        mmap = open(path, 'rb')
        lword = mmap.read(8)
        while len(lword) == 8:
            (val,) = struct.unpack('>Q', lword)
            mem[addr] = val
            addr += 8
            lword = mmap.read(8)
            if len(lword) != 8:
                print "mmap: throw away last %d bytes" % len(lword)

class State(object):
    def __init__(self):
        self.mem = Mem()
        self.instr = None
        self.cp0 = CP0()
        self.tlb = TLB()

    def tlb_map(self, va, write):
        return self.tlb.lookup(self.cp0.tlbEntry.hi.asid, va, write)

    def tlb_translate(state, va, write):
        top_bits = va >> 62
        if top_bits == 0:
            # user
            return state.tlb_map(va, write)
        elif top_bits == 1:
            # supervisor
            return state.tlb_map(va, write)
        elif top_bits == 2:
            #kernel unmapped
            return (None, va & 0x07ffffffffffffff)
        else:
            #kernel mapped
            if va >> 31 == 0x1ffffffff:
                # 32-bit compat
                va = va & 0x7fffffff
                if va & 0x40000000:
                    # mapped
                    return state.tlb_map(va, write)
                else:
                    # unmapped
                    return (None, va & 0x1fffffff)
            else:
                return state.tlb_map(va, write)
        return va
    
def inst_match(state,m):
    (instr_no, pc, enc) = m.groups()
    instr_no = long(instr_no)
    pc  = long(pc, 16)
    enc = long(enc, 16)
    if (instr_no & 0xfffff) == 0:
        print "instr %d" % instr_no
        
    instr = getattr(state, 'instr', None)
    if instr:
        if instr.instr_no != instr_no:
            print "Unterminated instr: %d" % instr
        elif instr.pc != pc:
            #print "Dup instr unmatched pc: %d 0x%x!=0x%x" % (instr.instr_no, instr.pc, pc)
            pass # this happens quite frequently for aborted instructions
        elif instr.enc != enc:
            print "%d: Dup instr unmatched enc: 0x%x!=0x%x" % (instr.instr_no, instr.enc, enc)
        else:
            pass # duplicate instr is OK...
    else:
        instr = Instr()
        instr.instr_no = instr_no
        instr.pc = pc
        instr.enc = enc
        state.instr = instr
    (ex, tlb_pc) = state.tlb_translate(pc, False)
    if ex:
        instr.exp = ex
        return
    aligned_pc= tlb_pc & 0xfffffffffffffff8
    if aligned_pc in state.mem:
        enc2 = state.mem[aligned_pc]
        if not (pc & 0x4):
            enc2 = enc2 >> 32
        else:
            enc2 = enc2 & 0xffffffff
        if enc != enc2 and aligned_pc not in ignore_list:
            print "%d: Wrong instruction fetch at 0x%x (0x%x) 0x%x!=0x%x" % (instr_no, pc, aligned_pc, enc, enc2)
    else:
        print "instr %d : 0x%x (0x%x) instruction fetch from uninitialised memory"  % (instr_no, pc, aligned_pc)

def dmem_match(state,m):
    if getattr(state.instr, 'dmem', None):
        print "%d: instr already has dmem!" % state.instr.instr_no
    state.instr.dmem = m

def exception_match(state, m):
    (exp_code, exp_str,m_badaddr) = m.groups()
    oldExp = getattr(state.instr, 'exp', None)
    if oldExp and not ((oldExp == "miss" and exp_str == 'Ex_TLBLoadInst') or (oldExp=="invalid" and exp_str == 'Ex_TLBInvInst')): # instruction miss is probably OK
        print "instr already has exp %s %s !" % (state.instr.exp, exp_str)
    (va, ba) = (None, None)
    if exp_str in ['Ex_TLBLoadInst', 'Ex_TLBInvInst']:
        va = state.instr.pc
    elif exp_str in ['Ex_TLBStore', 'Ex_TLBLoad', 'Ex_TLBLoadInv', 'Ex_TLBStoreInv', 'Ex_Modify']:
        #va = long(state.instr.dmem.group(3),16)
        pass # can't check this since cancelled...
    if m_badaddr is not None:
        ba = long(m_badaddr,16) & 0xfffffffffffffff8
    if ba != va and va is not None and not (ba is not None and (va & 0xfffffffffffffff8) == (ba & 0xfffffffffffffff8)):
        print "%d: Unmatched badaddr/va: %x!=%x" % (state.instr.instr_no, ba,va) # doesn't work for dmem now
    if ba is not None:
        state.cp0.tlbEntry.hi.r = (ba >> 62) & 3
        state.cp0.tlbEntry.hi.vpn2 = (ba & 0x3fffffffffffffffl) >> 13
    state.instr.exp = exp_code
    state.cp0.llAddr = None

def dropped_match(state, m):
    state.instr = Instr()

def ignore_match(state,m):
    pass

def boolstr(s):
    return s == "True"

def mkTLBEntry(groups):
    (r, vpn2, asid, valid, mask, g, lo0_pfn, lo0_cache, lo0_d, lo0_v, lo1_pfn, lo1_cache, lo1_d, lo1_v) = groups
    hi  = TLBEntryHi(long(r), long(vpn2, 16), boolstr(valid), long(mask, 16), boolstr(g), long(asid, 16))
    lo0 = TLBEntryLo(long(lo0_pfn, 16), lo0_cache, boolstr(lo0_d), boolstr(lo0_v), boolstr(g))
    lo1 = TLBEntryLo(long(lo1_pfn, 16), lo1_cache, boolstr(lo1_d), boolstr(lo1_v), boolstr(g))
    return TLBEntry(hi, lo0, lo1)

def tlb_write(state, m):
    groups = m.groups()
    (ir, idx) = groups[0:2]
    entry = mkTLBEntry(groups[2:])
    g = state.cp0.tlbEntry.lo0.g and state.cp0.tlbEntry.lo1.g
    state.cp0.tlbEntry.hi.g = g
    state.cp0.tlbEntry.lo0.g = g
    state.cp0.tlbEntry.lo1.g = g
    if not entry == state.cp0.tlbEntry:
        print "%s: Wrote wrong tlb entry expected: %s" % (state.instr.instr_no, state.cp0.tlbEntry)
    state.tlb.entries[long(idx, 10)] = entry

def entryhi_write(state, m):
    (priv, vpn, asid) = m.groups()
    state.cp0.tlbEntry.hi = TLBEntryHi(long(priv, 16), long(vpn, 16)/2, True, 0, False, long(asid, 16))

def entrylo_write(state, m):
    (loN, pfn, ca, d, v, g) = m.groups()
    eLo = TLBEntryLo(long(pfn, 16), ca, boolstr(d), boolstr(v), boolstr(g))
    if loN == '0':
        state.cp0.tlbEntry.lo0 = eLo
    else:
        state.cp0.tlbEntry.lo1 = eLo

def index_write(state, m):
    idx = long(m.group(1), 16)
    state.cp0.index = idx

def tlb_probe(state, m):
    (va, matched) = m.groups()
    va = long(va, 16)
    expVa = state.cp0.tlbEntry.hi.get_va()
    if va != expVa:
        print "%d: Wrong probe address: %x" % (state.instr.instr_no, expVa)
    (idx, match) = state.tlb.findMatch(state.cp0.tlbEntry.hi.asid, va)
    if bool(match) != (matched == "matched"):
        print "%d: Wrong probe matched: %s" % (state.instr.instr_no, match)
    if match:
        state.cp0.index = idx
    else:
        state.cp0.index |= 0x80000000

def tlb_read(state, m):
    idx = long(m.group(1))
    if idx != state.cp0.index:
        print "%d: wrong index for tlb read: %x" % (state.instr.instr_no, idx)
    entry = mkTLBEntry(m.groups()[1:])
    state.cp0.tlbEntry = entry

def blank_match(state, m):
    instr = getattr(state, 'instr')
    if not instr:
        return
    state.instr = None
    exp = getattr(instr, 'exp', None)
    instr.exp = None
    dmem = getattr(instr, 'dmem')
    instr.dmem = None
    theMem = state.mem
    if dmem:
        (wr,val,va,pa,mask,linked) = dmem.groups()
        isWrite = wr == "store"
        va = long(va, 16)
        pa = long(pa, 16)
        val = long(val, 16)
        mask = long(mask, 16)
        (tlbe, tlbpa) = state.tlb_translate(va, isWrite)
        if tlbe and not exp:
            print "%d : DMEM translate: got TLB %s error but no exp" % (instr.instr_no, tlbe)
        if not tlbe:
            if (tlbpa != pa):
                print "%d Wrong physical address 0x%x != 0x%x" % (instr.instr_no, tlbpa, pa)
            if isWrite:
                if not linked or (state.cp0.llAddr == pa):
                    old = long(theMem.get(pa, 0l))
                    m = getFullMask(mask)
                    new = (old & ~m) | (val & m)
                    theMem[pa] = new
                    state.c_stores += 1
            else:
                if linked:
                    state.cp0.llAddr = pa
                if pa not in ignore_list and pa not in theMem:
                    print "inst %d: Unitialised read from 0x%x" % (instr.instr_no, pa)
                    state.c_uninit += 1
                elif pa not in ignore_list and theMem[pa] != val:
                    print "inst %d: wrong read of 0x%x (0x%x)! " % (instr.instr_no, va, pa), "Expect 0x%x but was  0x%x" % (theMem[pa], val)
                    state.c_odd += 1
                else:
                    state.c_ok += 1

def parse_file(path):
    f = open(path, 'r')
    tlb_eh_re = 'TLBEntryHi { r: \'h(\d), vpn2: \'h([\da-f]+), asid: \'h([\da-f]+) }'
    tlb_el_re = 'TLBEntryLo { pfn: \'h([\da-f]+), cacheAlgorithm: (\w+), dirty: (True|False), valid: (True|False) }'
    tlb_elr_re = 'TLBEntryLoReg { lo: ' + tlb_el_re + ', global: (True|False) }'
    tlb_e_re = 'TLBEntry { assoc: TLBAssociativeEntry { entryHi: ' + tlb_eh_re + ', valid: (True|False), pageMask: \'h([\da-f]+), global: (True|False) }, lo: <V ' + tlb_el_re + ' ' + tlb_el_re + '  > }'
    matchers = [(re.compile(r), cb) for (r,cb) in (
        ('^inst +(\d+) ([\da-f]+) : ([\da-f]+)$', inst_match),
        ('^ +Reg +(\d+) <- ([\da-f]+)$', ignore_match),        
        ('^$', blank_match),
        ('^--$', ignore_match),
        ('^DMEM: (load|store) of 0x([\da-f]+) (?:to|from) 0x([\da-f]+) \(0x([\da-f]+)\) mask=([\da-f]+) (linked)?\s*$', dmem_match),
        ('^ +Branch dest=([\da-f]+)\s*$', ignore_match),
        ('^ +dropped$', dropped_match),
        ('^ +branch delay slot$', ignore_match),
        ('^ +HI/LO +<- +([\da-f]+)/([\da-f]+)\s*$', ignore_match),
        ('^ +(HI|LO) +<- +([\da-f]+)\s*$', ignore_match),
        ('^CP0: Status <- ', ignore_match),
        ('^CP0: [Ww]rite (indexed|random) TLB entry idx= *(\d+) ' + tlb_e_re, tlb_write),
        ('^CP0: EntryHi <- priv:(\d), vpn:([\da-f]+), asid:\s*(\d+)\s*$', entryhi_write),
        ('^CP0: EntryLo(0|1) <- ' + tlb_elr_re, entrylo_write),
        ('^CP0: Probe TLB for 0x([\da-f]+) (didn\'t match|matched)', tlb_probe),
        ('^CP0: Read TLB entry idx= *(\d+) ' + tlb_e_re, tlb_read),
        ('^CP0: Cause <- ', ignore_match),
        ('^CP0: Wired <- ', ignore_match),
        ('^CP0: PageMask <- ', ignore_match),
        ('^CP0: ExceptionPC <- ', ignore_match),
        ('^CP0: Compare <- ', ignore_match),
        ('^CP0: Index <- ([\da-f]+)$', index_write),
        ('^ +Exception! Code=([\da-f]+) ([\w_]+)(?: BadAddr=([\da-f]+))?\s*$', exception_match),
        ('^(?:CP0:)? +ERET to 0x([\da-f]+)\s*$', ignore_match),
    )]
    
    state = State()

    (state.c_ok, state.c_uninit, state.c_odd, state.c_stores) = (0L,0L,0L, 0L)
    skip = 28
    for line in f.xreadlines():
        if skip: # skip warnings at beginning
            skip -= 1
            continue
        m = None
        for (exp, cb) in matchers:
            m = exp.match(line)
            if m:
                #print line, " matched ", exp.pattern
                cb(state,m)
                break
        if not m:
            print "No match for ", line,

        
    print "ok: %d, uninit: %d, wrong: %d, stores: %d" % (state.c_ok, state.c_uninit, state.c_odd, state.c_stores)

    

if __name__=="__main__":
    parse_file(sys.argv[1])
