#-
# Copyright (c) 2012-2014 Michael Roe
# Copyright (c) 2012-2014 Robert M. Norton
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
# Test that csc does NOT raise an exception when storing an invalid, ephemeral
# capability via a capability with the store ephemeral bit unset.
#

class test_cp2_csc_ephemeral_invalid(BaseBERITestCase):
    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csc_ephemeral_invalid_dword0(self):
        '''Test csc stored an invalid ephemeral capability (perms)'''
        self.assertRegisterEqual(self.MIPS.s0, 0x00000000000000fc, "csc did not write an invalid, ephemeral capability (perms)")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csc_ephemeral_invalid_dword1(self):
        '''Test csc stored an invalid ephemeral capability (cursor)'''
        self.assertRegisterEqual(self.MIPS.s1, 0x0000000000000000, "csc did not write an invalid, ephemeral capability (cursor)")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csc_ephemeral_invalid_dword2(self):
        '''Test csc stored an invalid ephemeral capability (base)'''
        self.assertRegisterEqual(self.MIPS.s2, 0x0000000000000000, "csc did not write an invalid, ephemeral capability (base)")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csc_ephemeral_invalid_dword3(self):
        '''Test csc stored an invalid ephemeral capability (length)'''
        self.assertRegisterEqual(self.MIPS.s3, 0xffffffffffffffff, "csc did not write an invalid, ephemeral capability (length)")

    @attr('capabilities')
    def test_cp2_x_csc_ephermeral_invalid_2(self):
        '''Test csc does not raise an exception when the capbility is ephemeral and invalid and we don't have Permit_Store_Ephemeral permission'''
        self.assertRegisterEqual(self.MIPS.a2, 0,
            "csc raised an exception when the capability was ephemeral, but invalid")

