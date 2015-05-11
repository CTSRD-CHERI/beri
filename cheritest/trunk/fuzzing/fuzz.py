#!/usr/bin/env python
# Copyright (c) 2011 Robert M. Norton
# All rights reserved.
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

# Script to generate fuzz tests. This just generates .s files in
# tests/fuzz. The make file arranges to build and run them with
# bluesim and gxemul. tests/fuzz/test_fuzz.py is a nose test which
# compares the results.

import itertools, operator
import inspect
import string
import os, sys
import random

def make_list(s):
    return [l for l in map(str.strip, s.splitlines()) if l and l[0]!='#']

interesting_imm_values=make_list('''
0x0
0x1
# Max 5/6-bit shifts
0x1f
0x3f
# -1
0xffff
# min
0x8000
# max
0xefff
''')

non_zero_interesting_reg32_values=make_list('''
# 1,-1
0x1
0xffffffffffffffff
# 32-bit min, max
0xffffffff80000000
0x000000007fffffff
''')

non_zero_interesting_reg_values=non_zero_interesting_reg32_values + make_list('''
# 64-bit max. Note that 0x8000000000000000 is zero when viewed as a 32-bit integer
0x7fffffffffffffff
random
''')

interesting_reg32_values=['0']+non_zero_interesting_reg32_values
interesting_reg_values=['0','0x8000000000000000']+non_zero_interesting_reg_values

reg_reg_ops=make_list("""
    ADD
    ADDU
    SUB
    SUBU
    SLT
    SLTU
    AND
    OR
    XOR
    NOR
    SLLV
    SRA
    SRL
    DADD
    DADDU
    DSUB
    DSUBU
    DSLLV
    DSRA
    DSRL
    MOVZ
    MOVN
    MUL
""")

reg_imm_ops=make_list("""
    ADDI
    ADDIU
    SLTI
    SLTIU
    ANDI
    ORI
    XORI
    LUI
    DADDI
    DADDIU
    SLL
    SRA
    SRL
    DSLL
    DSRA
    DSRL
    DSLL32
    DSRL32
    DSRA32
""")

load_ops=make_list("""
    LB
    LBU
    LD
    LDL
    LDR
    LH
    LHU
    LW
    LWU
    LWL
    LWR
    #LL -- gxemul has a fit on unaligned LL!
    #LLD
""")

store_ops=make_list("""
    SB
    SD
    SDL
    SDR
    SH
    SW
    SWL
    SWR
    #SC
    #SCD
""")


mul_ops=make_list("""
    MULT
    MULTU
    DMULT
    DMULTU
""")

maddsub_ops=make_list('''
    MADD
    MADDU
    MSUB
    MSUBU
''')

div_ops=make_list("""
    DIV
    DIVU
    DDIV
    DDIVU
""")

one_arg_branches=make_list("""
    BGEZ
    BGTZ
    BLEZ
    BLTZ
    BGEZAL
    BLTZAL
    BGEZL
    BGTZL
    BLEZL
    BLTZL
    BGEZALL
    BLTZALL
""")

two_arg_branches=make_list("""
   BEQ
   BNE
   BEQL
   BNEL
""")

no_arg_branch_ops=make_list("""
   B
   BAL
""")

trap_ops=make_list("""
BREAK Breakpoint
SYSCALL System Call
TEQ Trap if Equal
TEQI Trap if Equal Immediate
TGE Trap if Greater or Equal
TGEI Trap if Greater of Equal Immediate
TGEIU Trap if Greater or Equal Immediate Unsigned
TGEU Trap if Greater or Equal Unsigned
TLT Trap if Less Than
TLTI Trap if Less Than Immediate
TLTIU Trap if Less Than Immediate Unsigned
TLTU Trap if Less Than Unsigned
TNE Trap if Not Equal
TNEI Trap if Not Equal Immediate
""")

misc_ops="""
CACHE Perform Cache Operation
DMFC0 Doubleword Move from Coprocessor 0
DMTC0 Doubleword Move to Coprocessor 0
ERET Exception Return
MFC0 Move from Coprocessor 0
MTC0 Move to Coprocessor 0
TLBP Probe TLB for Matching Entry
TLBR Read Indexed TLB Entry
TLBWI Write Indexed TLB Entry
TLBWR Write Random TLB Entry
WAIT Enter Standby Mode
"""

def generate_tests(options, group, variables):
    """
    A generic function for generating tests:
    options is the script options as returned by optparse,
    group is a string prefix which is used to determine the template name and test names.
    variables is a list of (varname, iterable) tuples representing the possible values taken
        by each variable varname in the template.
    """
    test_no=0
    fuzz_dir=os.path.dirname(inspect.getfile(inspect.currentframe()))
    template=string.Template(open(os.path.join(fuzz_dir,group+"_template.txt")).read())
    num_tests=reduce(operator.mul, [len(var[1]) for var in variables])
    sys.stdout.write("Generating %d %s tests..." % (num_tests, group))
    sys.stdout.flush()
    if options.count or (options.only and group!=options.only):
        print "skip."
        if options.count:
            return num_tests
        else:
            return 0
    for params in itertools.product(*[var[1] for var in variables]):
        test_name="test_fuzz_%s_%08d" % (group, test_no)
        test_path_base=os.path.join(options.test_dir,test_name)
        test_asm_path=test_path_base+".s"
        param_dict=dict(zip([var[0] for var in variables], params))
        for k,v in param_dict.iteritems():
            if v=="random":
                param_dict[k]="0x%016x"% random.randint(0,0xffffffffffffffff)
        param_dict['params_str']="\n".join("# %s: %s" % (k,("%d==0x%x" % (v,v&0xffffffffffffffff)) if type(v)==int else v) for k,v in param_dict.iteritems())
        if param_dict.has_key("nops"):
            param_dict["nops"]="\tnop\n" * param_dict["nops"]
        random.seed(test_no)
        test_asm=open(test_asm_path, 'w')
        test_asm.write(template.substitute(param_dict))
        test_asm.close()
        test_no+=1
    print "done."
    return test_no

def generate_load(options):
    return generate_tests(options, 'load', [
            ('op',load_ops),
            ('offset', range(7)),
            ('rs',['$0','$a0']),
            ('rt',['$0','$a0']),
            ('nops', range(7)),
            ])

def generate_store(options):
    return generate_tests(options, 'store', [
            ('op',store_ops),
            ('offset', range(7)),
            ('nops', range(7)),
            ])

def generate_loadstore(options):
    return generate_tests(options, 'loadstore', [
            ('load_op',load_ops),
            ('load_offset', range(7)),
            ('samesame', range(2)),
            ('store_op',store_ops),
            ('store_offset', range(7)),
            ])
    

def generate_arithmetic(options):
    #TODO $ra is also special...
    # rd0 is fixed as $a0
    rd0_regs=make_list("""
    $a0
    """)
    # rd1 is fixed as $a1
    rd1_regs=make_list("""
    $a1
    """)
    # source regs are either zero, same as rd0 or rd1
    source0_regs=make_list("""
    $zero
    $a0
    $a1
    """)
    source1_regs=make_list("""
    $a0
    $a1
    """)
    nops=[0,1,2,4]

    return generate_tests(
        options, 
        "alu_two_reg", 
        [ ('a0_val', ['random']), 
          ('a1_val', ['random']),
          ('op0', reg_reg_ops),
          ('rd0', rd0_regs),
          ('rs0', source0_regs),
          ('rt0', source0_regs),
          ('op1', reg_reg_ops),
          ('rd1', rd1_regs),
          ('rs1', source1_regs),
          ('rt1', source1_regs),
          ('nops', nops),])

def generate_arithmetic_single_reg_imm(options):
    return generate_tests(
        options,
        "alu_single_imm",
        [ ('op0', reg_imm_ops),
          ('a0_val', interesting_reg_values), 
          ('a1_val', interesting_imm_values),
        ])

def generate_arithmetic_single_reg_reg(options):
    return generate_tests(
        options,
        "alu_single_reg",
        [ ('op0', reg_reg_ops),
          ('a0_val', interesting_reg_values), 
          ('a1_val', interesting_reg_values),
        ])

def generate_mul_single(options):
    return generate_tests(
        options,
        "mul_single",
        [ ('op0', mul_ops),
          ('a0_val', interesting_reg_values), 
          ('a1_val', interesting_reg_values),
          ('nops', [0,1,2,4,8,16]),
        ])

int
def generate_maddsub_single(options):
    return generate_tests(
        options,
        "maddsub_single",
        [ ('op0', maddsub_ops),
          ('hi_val', interesting_reg32_values), 
          ('lo_val', interesting_reg32_values),
          ('a0_val', interesting_reg32_values), 
          ('a1_val', interesting_reg32_values),
          ('nops', [0]),
        ])

def generate_div_single(options):
    return generate_tests(
        options,
        "div_single",
        [ ('op0', div_ops),
          ('a0_val', interesting_reg_values), 
          ('a1_val', non_zero_interesting_reg_values),
          ('nops', [0,1,2,4,8,16]),
        ])

def generate_tlb(options):
    return generate_tests(
        options,
        "tlb",
        [ (
                'mode', 
                [0, 2] #kernel, user (supervisor not implemented on gxemul)
          ),
          (
                'page', 
                [0,1, 0x3ffff, 0x40000, 0x2000000, 0x3ffffff, 0x4000000, 0x7ffffff]
          ),
          (
                'segment', 
                [0,1,3] # no unmapped
          ),
          (
                'asid', 
                [0, 0xaa, 0xff]
          ),
          (
                'index', 
                [0,1,31,47]
          ),
          (
                'valid',
                [0,1],
          ),
          (
                'dirty',
                [0,1],
          ),
          (
                'cached', 
                [0,1] # gxemul dose not simulate a cache but this doesn't matter for test
          ),
        ]
    )

def generate_branch_one_arg(options):
    return generate_tests(
        options,
        "branch_one_arg", (
            ('op', one_arg_branches),
            ('arg_val', interesting_reg_values),
            # cannot test offsets -2 or -1  because of structure of test
            ('offset', map(lambda x: x*4,[-(2**15),-255,-7,-6,-5,-4,-3,0,1,2,3,4,5,6,7,0x100,0x7fff])),
))

def generate_branch_two_args(options):
    return generate_tests(
        options,
        "branch_two_args", (
            ('op', two_arg_branches),
            ('arg_val1', interesting_reg_values),
            ('arg_val2', interesting_reg_values),
            # cannot test offsets -2 or -1  because of structure of test
            ('offset', map(lambda x: x*4,[-(2**15),-255,-7,-6,-5,-4,-3,0,1,2,3,4,5,6,7,0x100,0x7fff])),
))

def generate_branch_no_args(options):
    return generate_tests(
        options,
        "branch_no_args", (
            ('op', no_arg_branch_ops),
            # cannot test offsets -2 or -1  because of structure of test
            ('offset', map(lambda x: x*4,[-(2**15),-255,-7,-6,-5,-4,-3,0,1,2,3,4,5,6,7,0x100,0x7fff])),
))

def generate_jump_register(options):
    return generate_tests(
        options,
        "jump_register", (
            ('link', [0,1]),
            ('targetreg', ['$a0', '$ra']),
            ('destreg', ['$zero','$ra','$a1']),
            ('offset', map(lambda x: x*4, [-5,-4,-2,1,2,4,5])),
            ('jitter', ['-3', '-2', '-1', '0', '1', '2', 3])
        ))

if __name__=="__main__":
    from optparse import OptionParser
    parser = OptionParser()
    parser.add_option("-d", "--test-dir",
                      help="Directory to generate tests in.", default="tests/fuzz")
    parser.add_option("-c", "--count",
                      help="Just count the tests, don't generate them.", action="store_true", default=False)
    parser.add_option("-o", "--only",
                      help="Only generate given test group.", default='')
    (options, args) = parser.parse_args()
    tests=0
    tests+=generate_arithmetic(options)
    tests+=generate_arithmetic_single_reg_reg(options)
    tests+=generate_arithmetic_single_reg_imm(options)
    tests+=generate_mul_single(options)
    tests+=generate_maddsub_single(options)
    tests+=generate_div_single(options)
    tests+=generate_load(options)
    tests+=generate_store(options)
    tests+=generate_loadstore(options)
    tests+=generate_tlb(options)
    tests+=generate_branch_one_arg(options)
    tests+=generate_branch_two_args(options)
    tests+=generate_branch_no_args(options)
    tests+=generate_jump_register(options)
    print "Total: %d tests." % tests


