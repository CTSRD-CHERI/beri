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
    return uu1 + (uu2 << 1) + (ut1 << 2) + (ut2 << 3) + (tt1 << 4) + (tt2 << 5)


class test_cp2_cne(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_cne_equal(self):
        '''Compare equal capabilities'''
        self.assertRegisterEqual(self.MIPS.a1, construct_answer(0,0,1,1,0,0), "Equal capabilities compare incorrectly")

    @attr('capabilities')
    def test_cp2_cne_bases_diff(self):
        '''Compare capabilities with different bases, offsets equal'''
        self.assertRegisterEqual(self.MIPS.a2, construct_answer(1,1,1,1,1,1), "Capabilities with different bases compared incorrectly")

    @attr('capabilities')
    def test_cp2_cne_offsets_diff(self):
        '''Compare capabilities with different offsets, bases equal'''
        self.assertRegisterEqual(self.MIPS.a3, construct_answer(1,1,1,1,1,1), "Capabilities with different offsets compared incorrectly")
        
    @attr('capabilities')
    def test_cp2_cne_base_and_offset_diff_sum_different(self):
        '''Compare capabilities with different base and offset, base+offset not equal'''
        self.assertRegisterEqual(self.MIPS.a4, construct_answer(1,1,1,1,1,1), "Capabilities with different base and offsets compared incorrectly")

    @attr('capabilities')
    def test_cp2_cne_base_and_offset_diff_sum_equal(self):
        '''Test capabilities with complimentary bases and offsets'''
        self.assertRegisterEqual(self.MIPS.a5, construct_answer(0,0,1,1,0,0), "Capabilities with equivalent base + offset compared incorrectly")
