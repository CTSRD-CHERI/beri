#-
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

from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr

class test_raw_srav_ex(BaseBERITestCase):

    @attr('ignorebadex')
    def test_a1(self):
        '''Test a SRAV of zero'''
        self.assertRegisterEqual(self.MIPS.a0, 0xfedcba9876543210, "Initial value from dli failed to load")
        self.assertRegisterEqual(self.MIPS.a1, 0x0000000076543210, "Shift of zero resulting in truncation failed")

    @attr('ignorebadex')
    def test_a2(self):
        '''Test a SRAV of one'''
        self.assertRegisterEqual(self.MIPS.a2, 0x000000003b2a1908, "Shift of one failed")

    @attr('ignorebadex')
    def test_a3(self):
        '''Test a SRAV of sixteen'''
        self.assertRegisterEqual(self.MIPS.a3, 0x0000000000007654, "Shift of sixteen failed")

    @attr('ignorebadex')
    def test_a4(self):
        '''Test a SRAV of 31(max)'''
        self.assertRegisterEqual(self.MIPS.a4, 0x0000000000000000, "Shift of thirty-one (max) failed")

    @attr('ignorebadex')
    def test_a6(self):
        '''Test a SRAV of zero with sign extension'''
        self.assertRegisterEqual(self.MIPS.a5, 0x00000000ffffffff, "Initial value from dli failed to load")
        self.assertRegisterEqual(self.MIPS.a6, 0xffffffffffffffff, "Shift of zero with sign extension failed")

    @attr('ignorebadex')
    def test_a7(self):
        '''Test a SRAV of one with sign extension'''
        self.assertRegisterEqual(self.MIPS.a7, 0xffffffffffffffff, "Shift of one with sign extension failed")

    @attr('ignorebadex')
    def test_t0(self):
        '''Test a SRAV of sixteen with sign extension'''
        self.assertRegisterEqual(self.MIPS.t0, 0xffffffffffffffff, "Shift of sixteen with sign extension failed")
