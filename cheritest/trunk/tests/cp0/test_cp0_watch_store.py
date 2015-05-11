#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2012 Robert M. Norton
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

class test_cp0_watch_store(BaseBERITestCase):
    @attr('watch')
    def test_watchLo_readback(self):
        '''Test that CP0 watchLo register write succeeded'''
        self.assertRegisterEqual(self.MIPS.a0 & 0xfffffff8, self.MIPS.a6 & 0xfffffff8, "CP0 watchLo register write failed")

    @attr('watch')
    def test_interrupt_fired(self):
        '''Test that watch triggered interrupt'''
        self.assertRegisterEqual(self.MIPS.a2, 1, "Exception didn't fire")

    @attr('watch')
    def test_eret_happened(self):
        '''Test that eret occurred'''
        self.assertRegisterEqual(self.MIPS.a1, 1, "Exception didn't return")

    @attr('watch')
    def test_cause_code(self):
        '''Test that exception code is set to "watch" in cause register.'''
        self.assertRegisterEqual((self.MIPS.a4 >> 2) & 0x1f, 23, "Cause not set to watch.")

    @attr('watch')
    def test_exl_in_handler(self):
        '''Test EXL set in status register.'''
        self.assertRegisterEqual((self.MIPS.a3 >> 1) & 0x1, 1, "EXL not set in exception handler")

    @attr('watch')
    def test_epc_in_handler(self):
        '''Test that EPC matches desired value (rounded down to 8 byte alignment)'''
        self.assertRegisterEqual(self.MIPS.a5 & 0xfffffffffffffff8, self.MIPS.a7 & 0xfffffffffffffff8, "EPC not correct in exception handler")


