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
# Test that cgetpccsetoffset raises a C2E exception if the capability register
# is one of the reserved registers, and the corresponding bit in PCC is not set.
#

class test_cp2_x_cgetpccsetoffset_reg(BaseBERITestCase):

    @attr('capabilities')
    def test_cp2_x_cgetpccsetoffset_reg_1(self):
        '''Test cgetpccsetoffset did not write to a reserved register'''
        self.assertRegisterEqual(self.MIPS.a0, 0,
            "cgetpccsetoffset wrote to a reserved register")

    @attr('capabilities')
    def test_cp2_x_cgetpccsetoffset_reg_2(self):
        '''Test cgetpccsetoffset did not write to a reserved register'''
        self.assertRegisterEqual(self.MIPS.a1, 8,
            "cgetpccsetoffset wrote to a reserved register")

    @attr('capabilities')
    def test_cp2_x_cgetpccsetoffset_reg_3(self):
        '''Test cgetpccsetoffset raised a C2E exception when register was reserved'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "cgetpccsetoffset did not raise an exception when register was reserved")

    @attr('capabilities')
    def test_cp2_x_cgetpccsetoffset_reg_4(self):
        '''Test capability cause was set correctly when register was reserved'''
        self.assertRegisterEqual(self.MIPS.a3, 0x181b,
            "Capability cause was not set correctly when register was reserved")

