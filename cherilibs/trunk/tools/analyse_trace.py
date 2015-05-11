#!/usr/bin/env python
#-
# Copyright (c) 2012, 2014 Robert M. Norton
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

import optparse, bisect, sys, subprocess, struct, re, os, functools
from collections import defaultdict
from cache import LruCache
import progress.bar as progress_bar
import csv

nm_re=re.compile('([0-9a-f]+) (.) ([$\.\w]+)')

#trace_res = {
# XXX update for cheri1
#'cheri1' : re.compile('inst \d+ ([\da-f]+) : [\da-f]+'),
#<instID>   T<Thread>: [<PC>] <result> inst=<encoding> (<n> dead cycles)
# result is '<reg><-<val>' or 'store' or 'branch/coproc'
#0       T0: [9000000040000000] fp<-0000000000000000 inst=3c1e0000 (0 dead cycles)
#'cheri2' : re.compile('(?P<instID>\d+)\s+T(?P<thread>\d+): \[(?P<pc>[0-9a-f]+)\][^i]*inst=(?P<inst>[0-9a-f]+)'),
#    'stream' : re.compile('^Time=\s+(?P<time>\d+) : (?P<pc>[0-9a-f]+): (?P<inst>[0-9a-f]+)\s+(?P<op>\w*)\s+(?P<args>[^D]*)DestReg <- 0x(?P<result>[0-9a-f]+) \{(?P<asid>[0-9a-f]+)}')
#}

def usage(msg):
    sys.stderr.write(msg + "\n")
    sys.exit(1)

exception_names = (
  "Interrupt",     # 0
  "Modify",        # 1
  "TLBLoad",       # 2
  "TLBStore",      # 3
  "AddrErrLoad",   # 4 ADEL
  "AddrErrStore",  # 5 ADES
  "InstBusErr",    # 6 // implementation dependent
  "DataBusErr",    # 7 // implementation dependent
  "SysCall",       # 8
  "BreakPoint",    # 9 
  "RI",            # 10 // reserved instruction exception (opcode not recognized) XXX could use better name
  "CoProcess1",    # 11 Attempted coprocessor inst for disabled coprocessor. Floating point emulation starts here.
  "Overflow",      # 12 Overflow from trapping arithmetic instructions (e.g. add, but not addu).
  "Trap",          # 13
  "CP2Trap",       # 14 CHERI2 INTERNAL
  "FloatingPoint", # 15
  "Exp16",         # 16 unused (was TLB cap load forbidden CHERI EXTENSION)
  "TLBStoreCap",   # 17 TLB cap store forbidden CHERI EXTENSION
  "CoProcess2",    # 18 Exception from Coprocessor 2 (extenstion to ISA)
  "TLBInstMiss",   # 19 CHERI2 INTERNAL
  "AddrErrInst",   # 20 CHERI2 INTERNAL
  "TLBLoadInvInst",# 21 CHERI2 INTERNAL
  "MDMX",          # 22 Tried to run an MDMX instruction but SR(dspOrMdmx) is not enabled.
  "Watch",         # 23 Physical address of load and store matched WatchLo/WatchHi registers
  "MCheck",        # 24 Disasterous error in control system, eg, duplicate entries in TLB.
  "Thread",        # 25 Thread related exception (check VPEControl(EXCPT))
  "DSP",           # 26 Unable to do DSP ASE Instruction (lack of DSP)
  "Exp27",         # 27 Place holder
  "TLBLoadInv",    # 28 CHERI2 INTERNAL
  "TLBStoreInv",   # 29 CHERI2 INTERNAL
  "CacheErr",      # 30 Parity/ECC error in cache.
  "None",          # No Error
)

exception_vectors = (
    (0xFFFFFFFFBFC00280, "kernel/bev_TLBMiss"       ),
    (0xFFFFFFFFBFC00300, "kernel/bev_CacheErr"      ),
    (0xFFFFFFFFBFC00380, "kernel/bev_common"        ),
    (0xFFFFFFFFBFC00480, "kernel/bev_CP2Trap"       ),
    (0xFFFFFFFF80000080, "kernel/vec_TLBMiss"       ),
    (0xFFFFFFFF80000100, "kernel/vec_CacheErr"      ),
    (0xFFFFFFFF80000180, "kernel/vec_common"        ),
    (0xFFFFFFFF80000280, "kernel/vec_CP2Trap"       ),
)

# values of the version field
version_noresult  = 0
version_alu       = 1
version_read      = 2
version_write     = 3
version_timestamp = 4
version_cap_cap   = 11
version_cap_clc   = 12
version_cap_csc   = 13

def is_mapped_addr(addr):
    if (addr & 0xffffffffc0000000) == 0xffffffff80000000:
        return False # 32-bit unmapped
    elif (addr & 0xc000000000000000) == 0x8000000000000000:
        return False # 64-bit unmapped
    else:
        return True

def get_page_no(addr, page_bits):
    if (addr & 0xffffffff80000000) == 0xffffffff80000000:
        return (0x1fffffff & addr) >> page_bits
    else:
        return (0x3fffffffffffffff & addr) >> page_bits

class ObjdumpDisassembler(object):
    def __init__(self, objdump, assembler):
        self.objdump = objdump
        self.assembler = assembler

    @LruCache()
    def disassemble(self, inst):
        tmp = os.tmpnam()
        p = subprocess.Popen([self.assembler, '-', '-o', tmp ], stdin=subprocess.PIPE)
        p.communicate(".text\n.word 0x%x\n" % inst)
        p.stdin.close()
        p.wait()
        disas = subprocess.check_output([self.objdump, '-d', tmp])
        os.unlink(tmp)
        opArg = disas.splitlines()[-1].split()
        if len(opArg) >= 4:
            return opArg[-2:]
        else:
            return (opArg[-1], '')
        return disas.splitlines()[-1].split()[2:]
    

class LLVMDisassmbler(object):
    def __init__(self, llvm_mc):
        self.llvm_mc = llvm_mc

    @LruCache()
    def disassemble(self, inst):
        p = subprocess.Popen([self.llvm_mc, '-disassemble', '-triple=cheri-unknown-freebsd'], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        (stdout, stderr) = p.communicate("0x%.2x 0x%.2x 0x%.2x 0x%.2x\n" % ((inst >> 24) & 0xff, (inst >> 16) & 0xff, (inst >> 8) & 0xff, inst & 0xff))
        p.stdin.close()
        x = p.wait()
        lines = stdout.splitlines()
        if len(lines) == 2:
            bits = lines[1].split()
            nbits = len(bits)
            if nbits >= 2:
                return (bits[0], ' '.join(bits[1:]))
            elif nbits == 1:
                return (bits[0], '')
        return ("0x%x" % inst, '')
        #print stdout, bits

def exe_exists(exe):
    try:
        subprocess.check_call([exe,'--help'], stdout=subprocess.PIPE)
    except:
        return False
    return True

def find_disassembler(opts):
    if opts.llvm_mc is not None:
        return LLVMDisassmbler(opts.llvm_mc)
    elif opts.objdump is not None:
        return ObjdumpDisassembler(opts.objdump, opts.assembler)
    elif exe_exists('llvm-mc'):
        return LLVMDisassmbler('llvm-mc')
    else:
        return ObjdumpDisassembler(opts.objdump, opts.assembler)

def get_names_file(name, nm_file, quiet, addr):
    for line in nm_file:
        m=nm_re.match(line)
        if not m :
            if not quiet: sys.stderr.write("Warning: unrecognized line in nm file: " + line)
            continue
        if m.group(2) in ('t', 'T'):
            yield (int(m.group(1), 16) + addr, "%s/%s" % (name, m.group(3)))

def get_names(options):
    names=[]
    for exe in options.elf:
        addr="0"
        if exe.find('@') != -1:
            (exe, addr) = exe.split('@')
        if not options.quiet:
            sys.stderr.write("Loading exe file %s\n" % exe)
        p = subprocess.Popen(['nm','--defined-only', exe],stdout=subprocess.PIPE)
        names.extend(get_names_file(exe, p.stdout, options.quiet, long(addr, 16)))
        p.wait()
    for nm in options.nm:
        if not options.quiet:
            sys.stderr.write("Parsing nm file %s\n" % options.nm_file)
        nm_file = open(options.nm_file, 'r')
        names.extend(get_names_file(nm, nm_file, options.quiet, 0))
    # Because the exception vectors are not labelled in the elf kernel's elf 
    # file we manually add symbols for them.
    names.extend(exception_vectors)
    # Sort by address
    names.sort(cmp=lambda x, y: cmp(x[0],y[0]))
    # Got the data, now merge duplicate symbols into one.
    if not options.quiet: sys.stderr.write("Merging duplicate symbols\n")
    unique_names=[]
    prev_addr, prev_name=0, 'null'
    for (addr, name) in names:
        if addr != prev_addr:
            unique_names.append((prev_addr, prev_name))
            prev_name = name
            prev_addr = addr
        else:
            prev_name = prev_name + '|' + name
    unique_names.append((prev_addr, prev_name))
    return unique_names

class Stats(object):
    tuple_fields = ('calls', 'insts','cycles', 'cpi', 'pcs','ipages','ipages all', 'dpages', 'dpages all', 'icache lines', 'dcache lines', 'loads', 'load_caps', 'stores', 'store_caps') + exception_names
    def __init__(self, iline_size, dline_size, page_bits):
        self.calls=0
        self.cycles=0
        self.insts=0
        self.exceptions = defaultdict(int)
        self.pcs = set()
        self.icache_lines = set()
        self.dcache_lines = set()
        # we keep two separate counts for TLB pages: the first counts
        # pages for MIPS taking account of unmapped kernel regions,
        # the second assumes all pages are mapped as on x86
        self.ipages = set()
        self.dpages = set()
        self.ipages_all = set()
        self.dpages_all = set()
        self.loads = 0
        self.load_caps = 0
        self.stores = 0
        self.store_caps = 0
        self.iline_size = iline_size
        self.dline_size = dline_size
        self.page_bits = page_bits

    def update(self, cycles=None, exception=None, pc=None, entry_type=None, mem_addr=None, call=False):
        self.insts += 1
        if call:
            self.calls+=1
        if cycles:
            self.cycles += cycles
        if exception != 31:
            self.exceptions[exception]+=1
        if pc is not None:
            self.pcs.add(pc)
            self.icache_lines.add(pc / self.iline_size)
            if is_mapped_addr(pc):
                self.ipages.add(get_page_no(pc, self.page_bits))
            self.ipages_all.add(pc >> self.page_bits)
        if entry_type == version_read:
            self.loads += 1
        elif entry_type == version_cap_clc:
            self.load_caps += 1
        elif entry_type == version_write:
            self.stores += 1
        elif entry_type == version_cap_csc:
            self.store_caps += 1
        if mem_addr is not None:
            self.dcache_lines.add(mem_addr / self.dline_size)
            if is_mapped_addr(mem_addr):
                self.dpages.add(get_page_no(mem_addr, self.page_bits))
            self.dpages_all.add(mem_addr >> self.page_bits)

    def as_tuple(self):
        return (self.calls, self.insts, self.cycles, float(self.cycles)/self.insts, len(self.pcs), len(self.ipages), len(self.ipages_all), len(self.dpages), len(self.dpages_all), len(self.icache_lines), len(self.dcache_lines), self.loads, self.load_caps, self.stores, self.store_caps) + tuple(self.exceptions[e] for e in xrange(len(exception_names)))

    def __repr__(self):
        if not self.insts:
            return "<empty>"
        else:
            return "insts=%5.5d cycles=% 5.5d cpi=%5.02f pcs=%d icache=%d dcache=%d loads=%d load_caps=%d stores=%d store_caps=%d %s " % (self.insts, self.cycles, float(self.cycles) / self.insts, len(self.pcs), len(self.icache_lines), len(self.dcache_lines), self.loads, self.load_caps, self.stores, self.store_caps, ' '.join('%s:%d' % (exception_names[ex] if ex < len(exception_names) else 'Ex_Unknown%d' % ex,c) for (ex, c) in self.exceptions.iteritems()))

def dump_stats(f, stats, use_csv):
    if use_csv:
        csvw = csv.writer(f, lineterminator='\n')
        csvw.writerow( ('key',) + Stats.tuple_fields)
        for key, stat in stats:
            key_str = hex(key) if type(key) in (int,long) else key
            csvw.writerow((key_str,) + stat.as_tuple())
    else:
        print '#Keys: ', len(stats)
        for key, stat in stats:
            print stat, key

def decodeShortWord(w):
    #ShortAddr
    #seg: word[62:59],    // 4
    #addrHi: word[39:32], // 8
    #addrLo: word[19:0]   // 20
    seg = (w>>28) & 0xf
    # top bit is 0 in user mode, 1 in kernel mode (supervisor not used)
    seghex = (seg << 3) | (0 if seg == 0 else 0x80)
    hi = (w >> 20) & 0xff
    lo = w & 0xfffff
    return "%02x....%02x...%05x" % (seghex,hi,lo)

def decodeCap(val1, val2):
    #val1 = struct.unpack('>Q',struct.pack('Q',val1))[0]
    #val2 = struct.unpack('>Q',struct.pack('Q',val2))[0]
    #ShortCap
    #Bool        isCapability; // 1
    #ShortPerms  perms;        // 8
    #Bool        sealed;       // 1
    #Bit#(22)    otype;        // 22
    #ShortAddr offset;         // 32
    #ShortAddr base;           // 32
    #ShortAddr length;         // 32
    #ShortPerms
    #Bool permit_seal;
    #Bool permit_store_ephemeral_cap;
    #Bool permit_store_cap;
    #Bool permit_load_cap;
    #Bool permit_store;
    #Bool permit_load;
    #Bool permit_execute;
    #Bool non_ephemeral;
    tag    = (val1 & 0x8000000000000000)
    perms  = (val1 >> 55)  & 0xff
    sealed = (val1 >> 54)  & 1
    otype  = (val1 >> 32) & 0x3fffff
    offset = (val1) & 0xffffffff
    base   = (val2 >> 32) & 0xffffffff
    length = (val2) & 0xffffffff
    cap   = ('V' if tag else 'v') + \
            ('T' if perms & 0x80 else 't') + \
            ('E' if perms & 0x40 else 'e') + \
            ('S' if perms & 0x20 else 's') + \
            ('L' if perms & 0x10 else 'l') + \
            ('W' if perms & 0x08 else 'w') + \
            ('R' if perms & 0x04 else 'r') + \
            ('X' if perms & 0x02 else 'x') + \
            ('G' if perms & 0x01 else 'g') + \
            " T%06x B%s o%s L%s" % (otype, decodeShortWord(base), decodeShortWord(offset), decodeShortWord(length))
    return cap


def annotate_trace(file_name, options):
    names = get_names(options)
    addresses=map(lambda x: x[0], names)
    syms = map(lambda x: x[1], names)
    disassembler = find_disassembler(options)

    # Open trace file and sniff file format
    v2_header = "\x82CheriStreamTrace"
    # pad to 32 bytes 
    v2_header = v2_header + '\0' * (34-len(v2_header))
    if file_name is None:
        trace_file=sys.stdin
    else:
        trace_file = open(file_name, 'r')
        if trace_file.read(len(v2_header)) == v2_header and not opts.version:
            if not opts.quiet:
                sys.stderr.write("Detected v2 trace format.\n")
            opts.version = 2

    # shape of an entry
    if opts.version == 2:
        s = struct.Struct('>BBHIQQQBB')
    else:
        s = struct.Struct('>BBHIQQQ')

    # field names for above
    field_version       ,\
    field_exception     ,\
    field_cycles        ,\
    field_opcode        ,\
    field_pc            ,\
    field_result1       ,\
    field_result2       ,\
    field_threadID      ,\
    field_asid          = range(9)

    if file_name is None:
        nentries = float('inf')
    else:
        trace_size = os.stat(file_name).st_size
        nentries = trace_size/s.size
        whence = 0 if opts.skip >= 0 else 2
        trace_file.seek(opts.skip * s.size, whence)
        nentries = nentries - opts.skip if opts.skip >= 0 else -opts.skip

    if opts.limit is not None:
        nentries = min(opts.limit, nentries)

    if not options.quiet: sys.stderr.write("%s: %f entries\n" % (file_name, nentries))

    if nentries < 0xfff or nentries == float('inf') or opts.quiet:
        bar = None
    else:
        bar = progress_bar.Bar('Processing', suffix='%(percent).1f%% - %(avg)f  %(elapsed_td)s / %(eta_td)s', max=nentries)

    cycle_count = 0
    inst_count  = 0
    next_pc     = None
    last_pc     = None
    last_cycles = None
    entry_no=0
    # maintain a set of unique instruction encodings encountered
    # this is mainly useful for sizing the disassembly cache 
    unique_opcodes = set()
    tracing = opts.start_pc == None and opts.start_inst == None
    start_inst = float('inf') if opts.start_inst is None else opts.start_inst
    stop_inst  = float('inf') if opts.stop_inst is None else opts.stop_inst
    branch_target = None
    iteration = 0
    if tracing and opts.cut:
        cut_file = open(opts.cut % iteration, 'w')
        if opts.version == 2:
            cut_file.write(v2_header)
    else:
        cut_file = None
    out_file = sys.stdout

    def newStats():
        return Stats(opts.icache_line, opts.dcache_line, opts.page_bits)

    inst_stats = defaultdict(newStats) if opts.inst_stats else None
    func_stats = defaultdict(newStats) if opts.func_stats else None
    if opts.ordered_func_stats:
        current_sym_name   = None
        ordered_func_stats = []
    all_stats  = newStats()            if opts.stats or opts.inst_stats or opts.func_stats or opts.ordered_func_stats else None

    while entry_no < nentries:
        if (bar is not None and entry_no & 0xfff == 0):
            bar.goto(entry_no)
        entry_no += 1

        e = trace_file.read(s.size)
        if len(e) < s.size:
            break # EOF

        f = s.unpack(e)

        entry_type = f[field_version]

        if entry_type >= 0x80:
            # skip header records, but still write them out
            if cut_file: cut_file.write(e)
            continue

        if entry_type == version_timestamp:
            # skip timestamp records, but still write them out because we might want them in future
            if cut_file: cut_file.write(e)
            new_cycle_count = f[field_result1]
            new_inst_count = f[field_result2]
            if tracing and opts.show and not opts.quiet:
                if cycle_count != new_cycle_count:
                    out_file.write("Warning: timestamp cycle count mismatch: %d != %d\n" % (cycle_count, new_cycle_count))
                if inst_count != new_inst_count:
                    out_file.write("Warning: timestamp instr count mismatch: %d != %d\n" % (inst_count, new_inst_count))
            cycle_count = new_cycle_count
            inst_count  = new_inst_count
            continue

        if entry_type in (version_cap_clc, version_cap_csc):
            # capability instructions don't give pc, so use one we made earlier
            pc = next_pc
        else:
            pc = f[field_pc]
            # currently this fails when PCC!=0 and on eret etc.
            #if next_pc is not None and pc != next_pc:
            #    if not opts.quiet: sys.stdout.write("Warning: predicted next PC did not match trace: %x!=%x\n" % (pc, next_pc))

        # sometimes entries are duplicated (e.g. after eret) -- skip them
        if pc == last_pc and f[field_cycles] == last_cycles:
            continue
        last_pc = pc

        inst_count += 1

        # calculate the next pc in case we need it. We will get it wrong in
        # some cases (e.g. branch likely, eret) but this does not matter
        # unless we land on a clc or csc. 
        if branch_target is not None:
            # branch delay slot, so use previously stored branch target
            next_pc   = branch_target
            branch_target = None
        elif entry_type in (version_noresult, version_alu) and opts.branch_pc:
            # these instructions might contain branch destination
            dest_pc = f[field_result1]
            if dest_pc != pc + 4:
                # it's a b5Cranch
                branch_target = dest_pc
                #if tracing: print "branch => %x" % branch_target
            next_pc = pc + 4 # XXX wrong for branch likely
        else:
            next_pc = pc + 4
        
        #print "%d, %x %x %s" % (entry_type, pc, next_pc, hex(f[field_result1]))

        if not tracing and (pc == opts.start_pc or inst_count >= start_inst):
            if not opts.quiet:
                sys.stderr.write("\nStart: iteration=%d pc=%x inst=%x\n" % (iteration, pc, inst_count))
            tracing = True
            if opts.cut:
                cut_file = open(opts.cut % iteration, 'w')
                if opts.version == 2:
                    cut_file.write(v2_header)
        elif tracing and (pc == opts.stop_pc or inst_count > stop_inst):
            if not opts.quiet:
                sys.stderr.write("\nStop: iteration=%d pc=%x inst=%x\n" % (iteration, pc, inst_count))
            tracing = False
                #start a new cut file for each iteration
            if cut_file: 
                cut_file.close()
                cut_file = None
            iteration += 1
            if inst_count > stop_inst:
                break
            continue
        elif not tracing or \
             (opts.user and (pc & 0xf000000000000000) != 0) or \
             (opts.kernel and (pc & 0xf000000000000000) == 0) or \
             (opts.asid is not None and opts.asid != f[field_asid]) or \
             (opts.thread is not None and opts.thread != f[field_threadID]):
            continue

        if cut_file:
            cut_file.write(e)

        i = bisect.bisect_right(addresses, pc)-1
        sym = syms[i]
        sym_addr = addresses[i]
        sym_off  = pc - sym_addr

        cycles = f[field_cycles]
        if last_cycles is None or cycles == last_cycles:
            # first instruction or dubious entry
            inst_cycles = 1
        elif cycles > last_cycles:
            inst_cycles = cycles - last_cycles
        else:
            inst_cycles = 0x400 + cycles - last_cycles # overflow
        last_cycles = cycles
        cycle_count += inst_cycles

        # the instruction encoding is little endian for some reason
        inst = struct.unpack('>I', struct.pack('=I', f[field_opcode]))[0]
        if opts.count_encs:
            unique_opcodes.add(inst)

        exception = f[field_exception]
        mem_addr =  f[field_result1] if entry_type in (version_read, version_write, version_cap_clc, version_cap_csc) else None
        if func_stats is not None: func_stats[sym].update(cycles=inst_cycles, exception=exception, pc=pc, entry_type=entry_type, mem_addr=mem_addr, call=(sym_off == 0))
        if inst_stats is not None: inst_stats[pc].update( cycles=inst_cycles, exception=exception, pc=pc, entry_type=entry_type, mem_addr=mem_addr)
        if all_stats is not None:  all_stats.update(      cycles=inst_cycles, exception=exception, pc=pc, entry_type=entry_type, mem_addr=mem_addr)
        if opts.ordered_func_stats:
            if current_sym_name != sym:
                current_sym_stats = newStats()
                current_sym_name = sym
                ordered_func_stats.append((current_sym_name, current_sym_stats))
            current_sym_stats.update(cycles=inst_cycles, exception=exception, pc=pc, entry_type=entry_type, mem_addr=mem_addr)
        if opts.show:
            data = None
            op, args = disassembler.disassemble(inst)
            inst_no = '%0.16x ' % inst_count if opts.show_inst else ''
            asid = '%0.2x ' % f[field_asid] if opts.version == 2 else ''
            threadID = '%0.2x ' % f[field_threadID] if opts.version == 2 else ''
            data = '=%0.16x' % f[field_result2]  if entry_type in (version_alu, version_write, version_read) else ' ' * 17
            addr = '@%0.16x' % mem_addr if mem_addr is not None else ' ' * 17
            e = '' if exception == 31 else 'EXCEPTION %s ' % exception_names[exception] if exception < len(exception_names) else 'UNNKOWN EXCEPTION %d:' % exception
            if entry_type in (version_cap_clc, version_cap_csc):
                data = decodeCap(f[field_result2], f[field_pc])
            if entry_type == version_cap_cap:
                data = decodeCap(f[field_result2], f[field_result1])
            out_file.write("%s%s%s%16x %-12ls %-20s %s %s %3d %s%s +0x%x\n" % (inst_no, threadID, asid, pc, op, args, data, addr, inst_cycles, e, sym, sym_off))
        if not tracing:
            # we've just stopped tracing
            last_cycles = None
    if bar is not None: bar.finish()
    if func_stats: dump_stats(sys.stdout, sorted(func_stats.iteritems()), opts.csv)
    if inst_stats: dump_stats(sys.stdout, sorted(inst_stats.iteritems()), opts.csv)
    if opts.ordered_func_stats:
        dump_stats(sys.stdout, ordered_func_stats, opts.csv)
    if all_stats:
        if opts.csv:
            out_file.write(','.join([file_name] + map(str,all_stats.as_tuple())) + '\n')
        else:
            print file_name, ':',  all_stats
    if opts.count_encs:
        sys.stderr.write("Unique encodings: %d\n" % len(unique_opcodes))

if __name__=="__main__":
    # patch optparse so that it does not reformat our epilogue
    optparse.OptionParser.format_epilog = lambda self, formatter: self.epilog
    parser = optparse.OptionParser("%prog [options] TRACE...", epilog="""
Key for capability tracing perms (upper case = set, lower case = unset):

V - Valid i.e. tag bit
T - set Type        (aka permit_seal)
E - store Ephemeral (aka local)
S - Store cap
L - Load cap
W - Write (data)
R - Read (data)
X - eXecute
G - Global (i.e. not local/ephemeral)
""")
    parser.add_option('--elf',        default=[], action='append', help="Elf file(s) containing symbol names")
    parser.add_option('--nm',         default=[], action='append', help="File(s) containing output by nm (alternative to elf file)")
    parser.add_option('--start-pc',   default=None, type = long, help="PC to start tracing")
    parser.add_option('--stop-pc',    default=None, type = long, help="PC to stop tracing")
    parser.add_option('--start-inst', default=None, type = long, help="Instruction number to start tracing (approx)")
    parser.add_option('--stop-inst',  default=None, type = long, help="Instruction number to stop tracing (approx)")
    parser.add_option('--user',       default=None, action='store_true', help="Only trace user instructions")
    parser.add_option('--kernel',     default=None, action='store_true', help="Only trace kernel instructions")
    parser.add_option('--asid',       default=None, type = int, help="Only trace instructions with given asid")
    parser.add_option('--thread',     default=None, type = int, help="Only trace instructions from given thread")
    parser.add_option('--count-encs', default=False, action='store_true', help="Count unique instruction encodings.")
    parser.add_option('--limit',      default=None, type = long, help="Maximum number of entries to trace")
    parser.add_option('--skip',       default=0, type = long, help="Number of entries to skip in trace (from end if negative)")
    parser.add_option('--show',       default=False, action='store_true', help="Print trace to stdout.")
    parser.add_option('--show-inst',  default=False, action='store_true', help="Show instruction number in trace.")
    parser.add_option('--cut',        default=False, action='store',      help="File pattern to dump iterations to -- must contain %%d.")
    parser.add_option('--func-stats', default=False, action='store_true', help="Print statistics for each function")
    parser.add_option('--ordered-func-stats', default=False, action='store_true', help="Print statistics for each function in execution order")
    parser.add_option('--inst-stats', default=False, action='store_true', help="Print statistics for each executed pc")
    parser.add_option('--stats',      default=False, action='store_true', help="Print overall statistics")
    parser.add_option('--icache-line', default=32, type=int, help="Size of icache line in bytes")
    parser.add_option('--dcache-line', default=32, type=int, help="Size of dcache line in bytes")
    parser.add_option('--page-bits',   default=12, type=int, help="Number of bits of offset in TLB page (e.g. 12=4k pages)")
    parser.add_option('--csv',        default=False, action='store_true', help="Print stats in csv")
    parser.add_option('--verbose',    default=True, dest='quiet', action='store_false', help="Be verbose.")
    parser.add_option('--llvm-mc',    default=None, help="Path to llvm-mc binary for disassembly.")
    parser.add_option('--objdump',    default=None, help="Path to objdump for disassembly (in combination with --as)")
    parser.add_option('--assembler',  default='mips64-as', help="Path to assembler for diassembly (in combination with --objdump).")
    parser.add_option('--version',    default=0, type=int, help="Trace format version.")
    parser.add_option('--branch-pc',  default=False, action='store_true', help="Assume the trace gives the target PC for branches (cheri1 does, cheri2 does not). If it does, we can use it to attempt to calculate the correct pc for capp. load/stores -- these would otherwise be incorrectly reported if they are the target of a branch.")

    #parser.add_option('-f','--format', dest="trace_format", help="Format of trace file (cheri2, stream, bin)", default='cheri2')

    (opts, args) = parser.parse_args()
    if opts.stats and opts.csv:
        print ','.join(('file',) +Stats.tuple_fields)
    if not args:
        annotate_trace(None, opts)
    for file_name in args:
        annotate_trace(file_name, opts)
