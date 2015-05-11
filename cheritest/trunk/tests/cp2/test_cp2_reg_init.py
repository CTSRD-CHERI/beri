#-
# Copyright (c) 2011 Robert N. M. Watson
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
# Check that a variety of CHERI specification properties are true.
#
# XXXRW notes:
#
# 1. The CHERI specification doesn't (quite) say what state the unsealed bit
#    should be in.  I am assuming 1 for all capabilities.
# 2. The CHERI specification doesn't say what type should be used.  I am
#    assuming 0x0 for all capabilities.
# 3. The CHERI specification suggests an initial base value of 2^64-1 for
#    general-purpose registers.  I am using 0 because that way we universally
#    use base 0x0 length 0x0 perms 0x0 for the 'null' capability -- except
#    for unsealed.  This might not be right -- unclear.
# 4. We don't currently have a syntax for indexed inspection of capability
#    registers, which is highly desirable for the general-purpose range.
#

class test_cp2_reg_init(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_reg_init_pcc(self):
        '''Test that CP2 register PCC is correctly initialised'''
        self.assertRegisterEqual(self.MIPS.pcc.base, 0x0, "CP2 PCC base incorrectly initialised")
        self.assertRegisterEqual(self.MIPS.pcc.length, 0xffffffffffffffff, "CP2 PCC length incorrectly initialised")
        self.assertRegisterEqual(self.MIPS.pcc.ctype, 0x0, "CP2 PCC ctype incorrectly initialised")
        self.assertRegisterEqual(self.MIPS.pcc.perms, 0x7fffffff, "CP2 PCC perms incorrectly initialised")
        self.assertRegisterEqual(self.MIPS.pcc.u, 0, "CP2 PCC sealed incorrectly initialised")

    @attr('capabilities')
    def test_cp2_reg_init_rest_base(self):
        '''Test that CP2 general-purpose register bases are correctly initialised'''
        for i in range(1, 26):
            self.assertRegisterEqual(self.MIPS.cp2[i].base, 0x0, "CP2 capability register bases incorrectly initialised")

    @attr('capabilities')
    def test_cp2_reg_init_rest_length(self):
        '''Test that CP2 general-purpose register lengths are correctly initialised'''
        for i in range(1, 26):
            self.assertRegisterEqual(self.MIPS.cp2[i].length, 0xffffffffffffffff, "CP2 capability register lengths incorrectly initialised")

    @attr('capabilities')
    def test_cp2_reg_init_rest_ctype(self):
        '''Test that CP2 general-purpose register ctypes are correctly initialised'''
        for i in range(1, 26):
            self.assertRegisterEqual(self.MIPS.cp2[i].ctype, 0x0, "CP2 capability register ctypes incorrectly initialised")

    @attr('capabilities')
    def test_cp2_reg_init_rest_perms(self):
        '''Test that CP2 general-purpose register perms are correctly initialised'''
        for i in range(1, 26):
            self.assertRegisterEqual(self.MIPS.cp2[i].perms, 0x7fffffff, "CP2 capability register perms incorrectly initialised")

    @attr('capabilities')
    def test_cp2_reg_init_rest_unsealed(self):
        '''Test that CP2 general-purpose register unsealeds are correctly initialised'''
        for i in range(1, 26):
            self.assertRegisterEqual(self.MIPS.cp2[i].u, 0, "CP2 capability register sealed incorrectly initialised")
