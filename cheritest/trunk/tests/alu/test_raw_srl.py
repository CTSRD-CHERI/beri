#-
# Copyright (c) 2014 Michael Roe
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

class test_raw_srl(BaseBERITestCase):

    def test_srl_0(self):
        '''Test SRL by 0 bits'''
        self.assertRegisterEqual(self.MIPS.a0, 0x76543210, "SRL by 0 bits failed")

    def test_srl_1(self):
        '''Test SRL by 1 bit'''
        self.assertRegisterEqual(self.MIPS.a1, 0x3b2a1908, "SRL by 1 bit failed")

    def test_srl_16(self):
        '''Test SRL by 16 bits'''
        self.assertRegisterEqual(self.MIPS.a2, 0x7654, "SRL by 16 bits failed")

    def test_srl_31(self):
        '''Test SRL by 31 bits'''
        self.assertRegisterEqual(self.MIPS.a3, 0x0, "SRL by 31 bits failed")

    def test_srl_0_neg(self):
        '''Test SRL by 0 bits of a negative value'''
        self.assertRegisterEqual(self.MIPS.a4, 0xfffffffffedcba98, "SRL by 0 bits of a negative value failed")

    def test_srl_1_neg(self):
        '''Test SRL by 1 bits of a negative value'''
        self.assertRegisterEqual(self.MIPS.a5, 0x7f6e5d4c, "SRL by 1 bit of a negative value failed")

    def test_srl_16_neg(self):
        '''Test SRL by 16 bits of a negative value'''
        self.assertRegisterEqual(self.MIPS.a6, 0xfedc, "SRL by 16 bits of a negative value failed")

    def test_srl_31_neg(self):
        '''Test SRL by 31 bits of a negative value'''
        self.assertRegisterEqual(self.MIPS.a7, 0x1, "SRL by 31 bits of a negative value failed")

