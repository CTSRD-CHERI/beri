#-
# Copyright (c) 2011 Steven J. Murdoch
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

class test_raw_lld(BaseBERITestCase):
    @attr('cached')
    def test_a0(self):
        '''Test load linked double word instruction'''
        self.assertRegisterEqual(self.MIPS.a0, 0xfedcba9876543210, "Double word load linked failed")

    @attr('cached')
    def test_a1(self):
        '''Test load linked positive double word'''
        self.assertRegisterEqual(self.MIPS.a1, 0x7fffffffffffffff, "Positive double word load linked failed")

    @attr('cached')
    def test_a2(self):
        '''Test load linked negative double word'''
        self.assertRegisterEqual(self.MIPS.a2, 0xffffffffffffffff, "Negative double word load linked failed")

    @attr('cached')
    def test_pos_offset(self):
        '''Test double word load linked at positive offset'''
        self.assertRegisterEqual(self.MIPS.a3, 2, "Double word load linked at positive offset failed")

    @attr('cached')
    def test_neg_offset(self):
        '''Test double word load linked at negative offset'''
        self.assertRegisterEqual(self.MIPS.a4, 1, "Double word load linked at negative offset failed")
