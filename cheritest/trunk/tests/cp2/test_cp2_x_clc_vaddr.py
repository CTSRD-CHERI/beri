#-
# Copyright (c) 2012 Michael Roe
# Copyright (c) 2013 Robert M. Norton
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
# Test that clc raises an exception if the address from which the capability
# is to be loaded is not aligned on a 32-byte boundary and that vaddr is correct.
#

class test_cp2_x_clc_vaddr(BaseBERITestCase):

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_x_clc_align_1_256(self):
        '''Test CLC did not load from an unaligned address'''
        self.assertRegisterEqual(self.MIPS.a0, 0,
            "CLC loaded from an unaligned address")

    @attr('capabilities')
    @attr('cap128')
    def test_cp2_x_clc_align_1_128(self):
        '''Test CLC did not load from an unaligned address'''
        self.assertRegisterEqual(self.MIPS.a0, 0,
            "CLC loaded from an unaligned address")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_x_clc_align_4_256(self):
        '''Test CLC did not load from an unaligned address'''
        self.assertRegisterEqual(self.MIPS.a1, 0,
            "CLC loaded from an unaligned address")

    @attr('capabilities')
    @attr('cap128')
    def test_cp2_x_clc_align_4_128(self):
        '''Test CLC did not load from an unaligned address'''
        self.assertRegisterEqual(self.MIPS.a1, 0,
            "CLC loaded from an unaligned address")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_x_clc_align_2_256(self):
        '''Test CLC raises an exception when the address is unaligned'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "CLC did not raise an exception when the address was unaligned")

    @attr('capabilities')
    @attr('cap128')
    def test_cp2_x_clc_align_2_128(self):
        '''Test CLC raises an exception when the address is unaligned'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "CLC did not raise an exception when the address was unaligned")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_x_clc_align_3_256(self):
        '''Test CP0 cause register was set correctly when address was unaligned'''
        self.assertRegisterEqual(self.MIPS.a3, 4*4,
            "CP0 status was not set to AdEL when the address was unaligned")

    @attr('capabilities')
    @attr('cap128')
    def test_cp2_x_clc_align_3_128(self):
        '''Test CP0 cause register was set correctly when address was unaligned'''
        self.assertRegisterEqual(self.MIPS.a3, 4*4,
            "CP0 status was not set to AdEL when the address was unaligned")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_x_clc_align_vaddr_256(self):
        '''Test CP0 badvaddr register was set correctly when address was unaligned'''
        self.assertRegisterEqual(self.MIPS.a4, self.MIPS.a6,
            "CP0 badvaddr was not set to cap1 when the address was unaligned")

    @attr('capabilities')
    @attr('cap128')
    def test_cp2_x_clc_align_vaddr_128(self):
        '''Test CP0 badvaddr register was set correctly when address was unaligned'''
        self.assertRegisterEqual(self.MIPS.a4, self.MIPS.a6,
            "CP0 badvaddr was not set to cap1 when the address was unaligned")
