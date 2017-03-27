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

class test_raw_fpu_abs_2008(BaseBERITestCase):

#
# This test for a 'not a number' value really should test that the fraction
# part is non-zero, as this denotes +/- infinity rather than NaN.
#
    def test_raw_fpu_abs_2008_1(self):
        '''Test single precision abs of QNaN'''
	self.assertRegisterMaskEqual(self.MIPS.a0, 0x7f800000, 0x7f800000, "ABS.S did not return QNaN")

    @attr('floatabs2008')
    def test_raw_fpu_abs_2008_2(self):
        '''Test that FCSR.ABS2008 is set'''
        self.assertRegisterEqual(self.MIPS.a1, 1, "FCSR.ABS2008 was not set")

    @attr('floatabs2008')
    def test_raw_fpu_abs_2008_3(self):
        '''Test that ABS.S has IEEE 754-2008 behaviour'''
        self.assertRegisterEqual(self.MIPS.a0, 0x7f900000, "ABS.S did not copy QNaN (IEEE 754-2008 behaviour")

    @attr('floatabs2008')
    def test_raw_fpu_abs_2008_4(self):
        '''Test that ABS.D has IEEE 754-2008 behaviour'''
        self.assertRegisterEqual(self.MIPS.a2, 0x7ff1000000000000, "ABS.D did not copy QNaN (IEEE 754-2008 behaviour")
