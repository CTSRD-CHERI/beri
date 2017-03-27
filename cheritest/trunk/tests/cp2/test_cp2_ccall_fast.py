#
# Copyright (c) 2016 Alexandre Joannou
# Copyright (c) 2013 Michael Roe
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
# Test a ccall_fast
#

class test_cp2_ccall_fast(BaseBERITestCase):

    @attr('capabilities')
    @attr('ccall_hw_2')
    def test_cp2_ccall_fast_1(self):
        '''Test that ccall_fast called the sandbox and returned'''
        self.assertRegisterEqual(self.MIPS.a1, 0x900d,
            "ccall did not call the sandbox and come back")

    @attr('capabilities')
    @attr('ccall_hw_2')
    def test_cp2_ccall_fast_2(self):
        '''Test that the sandbox inverted the memory array'''
        self.assertRegisterEqual(self.MIPS.a2, 0x08,
            "the sandbox did not invert the memory array")

    @attr('capabilities')
    @attr('ccall_hw_2')
    def test_cp2_ccall_fast_3(self):
        '''Test that the sandbox zeroed the second memory array'''
        self.assertRegisterEqual(self.MIPS.a3, 0x00,
            "the sandbox did not zero the second memory array")

    @attr('capabilities')
    @attr('ccall_hw_2')
    def test_cp2_ccall_fast_4(self):
        '''Test that returning from the sandbox cleared $a4'''
        self.assertRegisterEqual(self.MIPS.a4, 0x00,
            "returning from the sandbox did not clear $a4")

    @attr('capabilities')
    @attr('ccall_hw_2')
    def test_cp2_ccall_fast_5(self):
        '''Test that the sandbox zeroed the second memory array from $a4'''
        self.assertRegisterEqual(self.MIPS.a5, 0x00,
            "the sandbox did not zero the second memory array from $a4")
