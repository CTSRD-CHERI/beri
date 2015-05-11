#-
# Copyright (c) 2012 Michael Roe
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
# Test that storing a capability with an immediate offset works.
#

class test_cp2_csc_neg(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_csc_neg_underflow(self):
        '''Test that csc with negative immediate didn't overwrite dword before requested addr'''
        self.assertRegisterEqual(self.MIPS.a4, 0x0123456789abcdef, "csci underflow")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csci_neg_dword0(self):
        '''Test that csc with negative immediate stored perms, sealed and otype fields correctly'''
        self.assertRegisterEqual(self.MIPS.a0, 0x00000000000000fe, "csci stored incorrect sealed, perms, and otype fields")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csc_neg_dword1(self):
        '''Test that csc with negative immediate stored the offset field correctly'''
        self.assertRegisterEqual(self.MIPS.a1, 0x0000000000000001, "csci stored incorrect offset")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csc_neg_dword2(self):
        '''Test that csc with negative immediate stored the base field correctly'''
        self.assertRegisterEqual(self.MIPS.a2, 0x0000000000000000, "csci stored incorrect base address")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csc_neg_dword3(self):
        '''Test that csc with negative immediate stored the length field correctly'''
        self.assertRegisterEqual(self.MIPS.a3, 0xffffffffffffffff, "csci stored incorrect length")

    @attr('capabilities')
    def test_cp2_csc_neg_overflow(self):
        '''Test that csc with negative immediate didn't overwrite dword before requested addr'''
        self.assertRegisterEqual(self.MIPS.a5, 0x0123456789abcdef, "csci underflow")

