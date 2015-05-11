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

@attr('comparereg')
class test_cp0_compare(BaseBERITestCase):
    def test_compare_readback(self):
        '''Test that CP0 compare register write succeeded'''
        self.assertRegisterEqual(self.MIPS.a0, self.MIPS.a1, "CP0 compare register write failed")

    def test_cycle_count(self):
        ''' Test that cycle counter interrupted CPU at the right moment'''
	self.assertRegisterInRange(self.MIPS.a2, self.MIPS.a0 - 60, self.MIPS.a0 + 60, "Unexpected CP0 count cycle register value before compare register interrupt")

    @attr('cached')
    def test_cycle_count_cached(self):
        ''' Test that cycle counter interrupted CPU at the right moment'''
	self.assertRegisterInRange(self.MIPS.a2, self.MIPS.a0 - 30, self.MIPS.a0 + 30, "Unexpected CP0 count cycle register value before compare register interrupt")

    def test_interrupt_fired(self):
        '''Test that compare register triggered interrupt'''
        self.assertRegisterEqual(self.MIPS.a5, 1, "Exception didn't fire")

    def test_eret_happened(self):
        '''Test that eret occurred'''
        self.assertRegisterEqual(self.MIPS.a3, 1, "Exception didn't return")

#    def test_cause_bd(self):
#        '''Test that branch-delay slot flag in cause register not set in exception'''
#        self.assertRegisterEqual((self.MIPS.a7 >> 31) & 0x1, 0, "Branch delay (BD) flag set")

    def test_cause_ip(self):
        '''Test that interrupt pending (IP) bit set in cause register'''
        self.assertRegisterEqual((self.MIPS.a7 >> 8) & 0xff, 0x80, "IP7 flag not set")

    def test_cause_code(self):
        '''Test that exception code is set to "interrupt"'''
        self.assertRegisterEqual((self.MIPS.a7 >> 2) & 0x1f, 0, "Code not set to Int")

    def test_exl_in_handler(self):
        self.assertRegisterEqual((self.MIPS.a6 >> 1) & 0x1, 1, "EXL not set in exception handler")

    def test_cause_ip_cleared(self):
	'''Test that writing to the CP0 compare register cleared IP7'''
	self.assertRegisterEqual((self.MIPS.s0 >> 8) & 0xff, 0, "IP7 flag not cleared")

    def test_not_exl_after_handler(self):
        self.assertRegisterEqual((self.MIPS.a4 >> 1) & 0x1, 0, "EXL still set after ERET")

