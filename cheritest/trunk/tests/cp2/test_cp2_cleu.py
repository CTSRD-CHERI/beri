#-
# Copyright (c) 2014 Jonathan Woodruff
# Copyright (c) 2014 Robert M. Norton
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

from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr

#
# Test capability compare equal.
#

def construct_answer(tt1, tt2, ut1, ut2, uu1, uu2):
    # bit 0 -- both untagged swapped
    # bit 1 -- both untagged
    # bit 2 -- one untagged swapped
    # bit 3 -- one untagged 
    # bit 4 -- both tagged swapped
    # bit 5 -- both tagged
    return uu2 + (uu1 << 1) + (ut2 << 2) + (ut1 << 3) + (tt2 << 4) + (tt1 << 5)


class test_cp2_cleu(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_cleu_equal(self):
        '''Compare equal capabilities'''
        # A: base=0x42, offset=0x54
        # B: base=0x42, offset=0x54
        self.assertRegisterEqual(self.MIPS.a1, construct_answer(1,1,1,0,1,1), "Equal capabilities compare incorrectly")

    @attr('capabilities')
    def test_cp2_cleu_bases_diff(self):
        '''Compare capabilities with different bases, offsets equal'''
        # A: base=0x8000000000000000, offset=0x54
        # B: base=0x42, offset=0x54
        self.assertRegisterEqual(self.MIPS.a2, construct_answer(0,1,1,0,0,1), "Capabilities with different bases compared incorrectly")

    @attr('capabilities')
    def test_cp2_cleu_offsets_diff(self):
        '''Compare capabilities with different offsets, bases equal'''
        # A: base=0x42, offset=0x8000000000000000
        # B: base=0x42, offset=0x54
        self.assertRegisterEqual(self.MIPS.a3, construct_answer(0,1,1,0,0,1), "Capabilities with different offsets compared incorrectly")
        
    @attr('capabilities')
    def test_cp2_cleu_base_and_offset_diff_sum_different(self):
        '''Compare capabilities with different base and offset, base+offset not equal'''
        # A: base=0x1, offset=0x8000000000000000
        # B: base=0x42, offset=0x54
        self.assertRegisterEqual(self.MIPS.a4, construct_answer(0,1,1,0,0,1), "Capabilities with different base and offsets compared incorrectly")

    @attr('capabilities')
    def test_cp2_cleu_base_and_offset_diff_sum_equal(self):
        '''Test capabilities with complimentary bases and offsets'''
        # A: base=0x8000000000000053, offset=0x8000000000000001
        # B: base=0x42, offset=0x54
        self.assertRegisterEqual(self.MIPS.a5, construct_answer(1,1,1,0,1,1), "Capabilities with equivalent base + offset compared incorrectly")
