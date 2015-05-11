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

#
# Test IEEE 747 infinity values in single-precision arithmetic
#

from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr

class test_raw_fpu_mul_inf_single(BaseBERITestCase):

    def test_raw_fpu_mul_inf_single_1(self):
        '''Test mul.s of 1.0 and +infinity'''
	self.assertRegisterEqual(self.MIPS.a0, 0x7f800000, "mul.s of 1.0 and +infinity did not give +infinity")

    def test_raw_fpu_mul_inf_single_2(self):
        '''Test mul.s of +Infinity and 0.0'''
        self.assertRegisterMaskEqual(self.MIPS.a1, 0xff800000, 0x7f800000, "mul.s of +infinity and 0.0 did not give NaN")

    def test_raw_fpu_mul_inf_single_3(self):
        '''Test mul.s of +Infinity and 0.0'''
        self.assertRegisterMaskNotEqual(self.MIPS.a1, 0x7fffff, 0, "mul.s of +infinity and 0.0 did not give NaN")

