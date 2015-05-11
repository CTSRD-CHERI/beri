#! /usr/bin/env python

#-
# Copyright (c) 2014 Colin Rothwell
# All rights reserved.
#
# This software was developed by Colin Rothwell as part of his final year
# undergraduate project
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

import sys
from subprocess import check_output

def zero_reg(register):
    return 'add ${0}, $0, $0'.format(register)

def load_i(register, hex_string):
    return 'li ${0}, 0x{1}'.format(register, hex_string)

def or_i(register, octet):
    return 'ori ${0}, ${0}, 0x{1}'.format(register, octet)

def shift_left(register, amount):
    return 'dsll ${0}, ${0}, {1}'.format(register, amount)

def move_word_to_fpu(from_reg, fpu_reg):
    return 'mtc1 ${0}, ${1}'.format(from_reg, fpu_reg)

def move_double_to_fpu(from_reg, fpu_reg):
    return 'dmtc1 ${0}, ${1}'.format(from_reg, fpu_reg)

def perform_monodic_op(op, arg):
    return '{0} ${1}, ${1}'.format(op, arg)

def perform_diadic_op(op, left_arg, right_arg):
    return '{0} ${1}, ${1}, ${2}'.format(op, left_arg, right_arg)

def move_word_from_fpu(to_reg, fpu_reg):
    return 'mfc1 ${0}, ${1}'.format(to_reg, fpu_reg)

def move_double_from_fpu(to_reg, fpu_reg):
    return 'dmfc1 ${0}, ${1}'.format(to_reg, fpu_reg)

def single_to_hex(single):
    return check_output(['./single_to_hex', single]).strip()

def double_to_hex(double):
    return check_output(['./double_to_hex', double]).strip()

def load_double_word(register, hex_string):
    instructions = []
    shift_amt = 16
    for i in range(0, 16, 4):
        hextet = hex_string[i:i+4]
        if hextet != '0000':
            instructions.append(shift_left(register, shift_amt))
            instructions.append(or_i(register, hextet))
            shift_amt = 0
        shift_amt += 16 

    if hextet == '0000':
        instructions.append(shift_left(register, shift_amt - 16))

    # Don't need first shift, but do need to zero register!
    instructions[0] = zero_reg(register)

    return '\n'.join(instructions)

def load_single_word(register, hex_string):
    return load_i(register, hex_string)

def load_double(register, double):
    instructions = load_double_word(register, double_to_hex(double))
    return '# Loading {0}\n{1}'.format(double, instructions)

def load_single(register, single):
    instructions = load_single_word(register, single_to_hex(single))
    return '# Loading {0}\n{1}'.format(single, instructions)

def load_paired_single(register, paired_single):
    paired_hex = map(single_to_hex, paired_single)
    instructions = load_double_word(register, ''.join(paired_hex))
    psl, psh = paired_single
    return '# Loading ({0}, {1})\n{2}'.format(psl, psh, instructions)

def main():
    help_string = ''.join((
        'Usage: {0} \n'.format(sys.argv[0]), 
        '\t<s(ingle)|d(ouble)|ps> <m(onodic)|d(iadic)> ...\n',
        '\t<operation> <result reg> ...\n',
        '\t<left fpu reg> <left operand> (PS only: <left high operand>) ...\n',
        '\t(Diadic only: <right fpu reg> <right operand> '
        '(PS only: <right high operand>))'
    ))
    if len(sys.argv) < 7:
        print help_string
        return 1

    data_type = sys.argv[1].strip().lower()

    if data_type not in ('s', 'd', 'ps'):
        print 'Data type must be either _s_ingle, _d_ouble or _p_aired_s_ingle'
        return 2

    arity = {'m': 1, 'd': 2}.get(sys.argv[2][0].lower(), None)

    if arity is None:
        print 'Arity must be either _m_onadic or _d_iadic'
        return 3

    if data_type in ('s', 'd'):
        if arity == 1:
            wrong_arg_count = (len(sys.argv) != 7)
        else:
            wrong_arg_count = (len(sys.argv) != 9)
    else: # data_type is 'ps'
        if arity == 1:
            wrong_arg_count = (len(sys.argv) != 8)
        else:
            wrong_arg_count = (len(sys.argv) != 11)
    
    if wrong_arg_count:
        print 'Wrong number of arguments for specified format and arity.'
        print help_string
        return 1

    operation = sys.argv[3]
    result_reg = sys.argv[4]
    left_fpu_reg = sys.argv[5]
    left_op = sys.argv[6]
    if data_type == 'ps':
        left_op = (left_op, sys.argv[7])
        if arity == 2:
            right_fpu_reg = sys.argv[8]
            right_op = (sys.argv[9], sys.argv[10])
    elif arity == 2:
        right_fpu_reg = sys.argv[7]
        right_op = sys.argv[8]

    if data_type == 's':
        load = load_single
        move_to = move_word_to_fpu
        move_from = move_word_from_fpu
    elif data_type == 'ps':
        load = load_paired_single
        move_to = move_double_to_fpu
        move_from = move_double_from_fpu
    else:
        load = load_double
        move_to = move_double_to_fpu
        move_from = move_double_from_fpu

    print load(result_reg, left_op)
    print move_to(result_reg, left_fpu_reg)

    if arity == 2:
        print load(result_reg, right_op)
        print move_to(result_reg, right_fpu_reg)
    print '# Performing operation'
    if arity == 2:
        print perform_diadic_op(operation, left_fpu_reg, right_fpu_reg)
    else:
        print perform_monodic_op(operation, left_fpu_reg)
    print move_from(result_reg, left_fpu_reg)

if __name__ == '__main__':
    main()
