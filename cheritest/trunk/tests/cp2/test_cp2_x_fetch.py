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
# Test that an exception is raised when the program counter exceeds
# PCC.base + PCC.length (i.e. the program runs off the end of the code
# segment).
#

class test_cp2_x_fetch(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_x_fetch_1(self):
        '''Test cannot run code beyond PCC.length'''
        self.assertRegisterEqual(self.MIPS.a0, 1,
            "Executed code beyond PCC.length")

    @attr('capabilities')
    def test_cp2_x_fetch_2(self):
        '''Test instruction fetch raises an exception'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "Instruction fetch did not raise an exception when PCC.length exceeded")

    @attr('capabilities')
    def test_cp2_x_fetch_3(self):
        '''Test that exception during instruction fetch sets cause register'''
        self.assertRegisterEqual(self.MIPS.a3, 0x01ff,
            "Exception during Instruction fetch did not set cause register correctly")

