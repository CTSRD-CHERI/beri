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

#
# Test that values placed in one capability register, then moved to another,
# can be read back correctly.
#

class test_cp2_cmove(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_cmove_uperms(self):
        '''Test that cmove retained perms fields correctly'''
        self.assertRegisterEqual(self.MIPS.a0, 0xff, "cmove failed to retain correct perms field")

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
