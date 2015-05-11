#-
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

#
# Test conversion from a 64-bit int to a double-precision floating point value
#

from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr

class test_raw_fpu_cvt_d_l_d64(BaseBERITestCase):

    @attr('float64')
    def test_raw_fpu_cvt_d_l_d64_1(self):
        '''Test cvt.d.l of 0'''
	self.assertRegisterEqual(self.MIPS.a0 , 0, "0 did not convert to 0.0")

    @attr('float64')
    def test_raw_fpu_cvt_d_l_d64_2(self):
        '''Test cvt.d.l of 1'''
	self.assertRegisterEqual(self.MIPS.a1 , 0x3ff0000000000000, "1 did not convert to 1.0")

    @attr('float64')
    def test_raw_fpu_cvt_d_l_d64_3(self):
        '''Test cvt.d.l of 0x100000001'''
	self.assertRegisterEqual(self.MIPS.a2, 0x41f0000000100000, "2^32 + 1 did not convert to 4294967297.0")
