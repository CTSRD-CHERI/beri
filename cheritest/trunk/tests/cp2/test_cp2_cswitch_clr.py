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
# Full capability context switch test -- with clear.
#

class test_cp2_cswitch_clr(BaseBERITestCase):
    @attr('capabilities')
    def test_unsealed(self):
        for i in range(0, 28):
            self.assertRegisterEqual(self.MIPS.cp2[i].u, 0, "u bit incorrect after context switch")
        self.assertRegisterEqual(self.MIPS.cp2[31].u, 0, "u bit incorrect after context switch")

    @attr('capabilities')
    def test_perms(self):
        for i in range(0, 28):
            self.assertRegisterEqual(self.MIPS.cp2[i].perms, 0x7fffffff, "perms incorrect after context switch")
        self.assertRegisterEqual(self.MIPS.cp2[31].perms, 0x7fffffff, "perms incorrect after context switch")

    @attr('capabilities')
    def test_base(self):
        for i in range(0, 28):
            self.assertRegisterEqual(self.MIPS.cp2[i].base, 0x0, "base incorrect after context switch")
        self.assertRegisterEqual(self.MIPS.cp2[31].base, 0x0, "base incorrect after context switch")

    @attr('capabilities')
    def test_length(self):
        for i in range(0, 28):
            self.assertRegisterEqual(self.MIPS.cp2[i].length, 0xffffffffffffffff, "length incorrect after context switch")
        self.assertRegisterEqual(self.MIPS.cp2[31].length, 0xffffffffffffffff, "length incorrect after context switch")

    @attr('capabilities')
    def test_offset(self):
        for i in range(0, 28):
            self.assertRegisterEqual(self.MIPS.cp2[i].offset, 0x0, "offset incorrect after context switch")
        self.assertRegisterEqual(self.MIPS.cp2[31].offset, 0x0, "offset incorrect after context switch")
