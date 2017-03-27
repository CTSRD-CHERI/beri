#
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

#
# Test the CP0 config2 register
#

class test_cp0_config2(BaseBERITestCase):

    @attr('config2')
    def test_cp0_config2_exists(self):
        '''Test CP0.Config2 exists'''
        self.assertRegisterEqual(self.MIPS.a4, 2,
            "CP0 does not have config register 2")

    @attr('config2')
    @attr('beri1cache')
    def test_cp0_config2_sa_beri1(self):
        '''Test the value of CP0.Config2.SA'''
        self.assertRegisterMaskEqual(self.MIPS.a2, 0xf, 3, "Config2 has unexpected value for L2 cache associativity")

    @attr('config2')
    @attr('beri2cache')
    def test_cp0_config2_sa_beri2(self):
        '''Test the value of CP0.Config2.SA'''
        self.assertRegisterMaskEqual(self.MIPS.a2, 0xf, 3, "Config2 has unexpected value for L2 cache associativity")

    @attr('config2')
    @attr('beri1cache')
    def test_cp0_config2_sl_beri1(self):
        '''Test the value of CP0.Config2.SL'''
        self.assertRegisterMaskEqual(self.MIPS.a2, 0xf0, 0x60, "Config2 has unexpected value for L2 cache line size")

    @attr('config2')
    @attr('beri2cache')
    def test_cp0_config2_sl_beri2(self):
        '''Test the value of CP0.Config2.SL'''
        self.assertRegisterMaskEqual(self.MIPS.a2, 0xf0, 0x40, "Config2 has unexpected value for L2 cache line size")

    @attr('config2')
    @attr('beri1cache')
    def test_cp0_config2_ss_beri1(self):
        '''Test the value of CP0.Config2.SS'''
        self.assertRegisterMaskEqual(self.MIPS.a2, 0xf00, 0x300, "Config2 has unexpected value for number of L2 index positions")

    @attr('config2')
    @attr('beri2cache')
    def test_cp0_config2_ss_beri2(self):
        '''Test the value of CP0.Config2.SS'''
        self.assertRegisterMaskEqual(self.MIPS.a2, 0xf00, 0x600, "Config2 has unexpected value for number of L2 index positions")


