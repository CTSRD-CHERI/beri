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

#
# Test for a control flow problem with a particular version of Cheri2.
# A CP2 instruction followed by a jump caused the jump to be skipped.
#

class test_cp2_cmove_j(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_cmove_uperms(self):
        '''Test that cmove retained u, perms fields correctly'''
        self.assertRegisterEqual(self.MIPS.a0, 0xff, "cmove failed to retain correct u, perms fields")

    @attr('capabilities')
    def test_cp2_cmove_offset(self):
        '''Test that cmove retained the offset field correctly'''
        self.assertRegisterEqual(self.MIPS.a1, 0x5, "cmove failed to retain correct offset")

    @attr('capabilities')
    def test_cp2_cmove_base(self):
        '''Test that cmove retained the base field correctly'''
        self.assertRegisterEqual(self.MIPS.a2, 0x100, "cmove failed to retain correct base address")

    @attr('capabilities')
    def test_cp2_cmove_length(self):
        '''Test that cmove retained the length field correctly'''
        self.assertRegisterEqual(self.MIPS.a3, 0x200, "cmove failed to retain correct length")

    @attr('capabilities')
    def test_branch_delay(self):
        '''Test that branch delay was executed.'''
        self.assertRegisterEqual(self.MIPS.a4, 0x1, "branch delay not executed")

    @attr('capabilities')
    def test_jump_taken(self):
        '''Test jump taken.'''
        self.assertRegisterEqual(self.MIPS.a5, 0x0, "jump did not skip over instruction.")

    @attr('capabilities')
    def test_jump_dest(self):
        '''Test jump destination reached.'''
        self.assertRegisterEqual(self.MIPS.a6, 0x1, "jump did not reach destination.")
