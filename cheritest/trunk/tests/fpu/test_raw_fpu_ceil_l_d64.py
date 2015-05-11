#-
# Copyright (c) 2013-2014 Michael Roe
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
# Test double-precision ceiling operation when the FPU is in 64 bit mode
#

from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr

class test_raw_fpu_ceil_l_d64(BaseBERITestCase):

    @attr('float64')
    def test_raw_fpu_ceil_l_d64_1(self):
        '''Test double precision ceil.l of -0.75'''
	self.assertRegisterEqual(self.MIPS.a0 , 0, "-0.75 did not round up to 0")

    @attr('float64')
    def test_raw_fpu_ceil_l_d64_2(self):
        '''Test double precision ceil.l of -0.5'''
	self.assertRegisterEqual(self.MIPS.a1 , 0, "-0.5 did not round up to 0")

    @attr('float64')
    def test_raw_fpu_ceil_l_d64_3(self):
        '''Test double precision ceil.l of -0.25'''
	self.assertRegisterEqual(self.MIPS.a2, 0, "-0.25 did not round up to 0")

    @attr('float64')
    def test_raw_fpu_ceil_l_d64_4(self):
        '''Test double precision ceil.l of 0.5'''
	self.assertRegisterEqual(self.MIPS.a3, 1, "0.5 did not round up to 1")

    @attr('float64')
    def test_raw_fpu_ceil_l_d64_5(self):
        '''Test double precision trunc.l of 1.5'''
	self.assertRegisterEqual(self.MIPS.a4, 2, "1.5 did not round up to 2")

    @attr('float64')
    def test_raw_fpu_ceil_l_d64_6(self):
        '''Test ceiling of double precision to 64 bit int'''
        self.assertRegisterEqual(self.MIPS.a5, 0x10000000000001, "2^52 + 1 was not correctly converted from double precision to a 64 bit integer")


