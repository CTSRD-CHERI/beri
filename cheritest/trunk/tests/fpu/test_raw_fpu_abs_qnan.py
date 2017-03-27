#-
# Copyright (c) 2014, 2016 Michael Roe
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

#
# Test abs.s of "Quiet Not a Number" (QNaN)
#

from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr

class test_raw_fpu_abs_qnan(BaseBERITestCase):

    def test_raw_fpu_abs_qnan_1(self):
        '''Test ABS.S of QNaN'''
	self.assertRegisterIsSingleNaN(self.MIPS.a0, "ABS.S did not return NaN")

    @attr('floatlegacyabs')
    def test_raw_fpu_abs_qnan_2(self):
        '''Test that ABS.S has IEEE 754-1985 behaviour'''
        self.assertRegisterMaskEqual(self.MIPS.a0, 0xff800000, 0xff800000, "ABS.S did not copy QNaN (IEEE 754-1985 behaviour")

    @attr('floatlegacyabs')
    @attr('floatechonan')
    def test_raw_fpu_abs_qnan_3(self):
        '''Test that ABS.S echos QNaN'''
        self.assertRegisterEqual(self.MIPS.a0, 0xffffffffff900000, "ABS.S did not echo QNaN")

    def test_raw_fpu_abs_qnan_4(self):
        '''Test ABS.D of QNaN'''
        self.assertRegisterMaskEqual(self.MIPS.a2, 0x7ff0000000000000, 0x7ff0000000000000, "ABS.D did not return QNaN")

    @attr('floatlegacyabs')
    def test_raw_fpu_abs_qnan_5(self):
        '''Test that ABS.D has IEEE 754-1985 behavior'''
        self.assertRegisterMaskEqual(self.MIPS.a2, 0xfff0000000000000, 0xfff0000000000000, "ABS.D did not copy QNaN (IEEE 754-1985 behaviour")

    @attr('floatlegacyabs')
    @attr('floatechonan')
    def test_raw_fpu_abs_qnan_6(self):
        '''Test that ABS.D echos QNaN'''
        self.assertRegisterEqual(self.MIPS.a2, 0xfff1000000000000, "ABS.D did not echo QNaN")

    @attr('floatlegacyabs')
    def test_raw_fpu_abs_qnan_7(self):
        '''Test that FCSR.ABS2008 is not set'''
        self.assertRegisterEqual(self.MIPS.a1, 0, "FCSR.ABS2008 was set")
