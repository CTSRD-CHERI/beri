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
# Test lbu (load byte unsigned) indirected via a constrainted c0.
#

class test_cp2_c0_lbu(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_lbu_64aligned(self):
        '''Test a 64-bit aligned byte load via a constrained c0'''
        self.assertRegisterEqual(self.MIPS.a0, 0x00, "64-bit aligned lbu returned incorrect value")

    @attr('capabilities')
    def test_cp2_lbu_32aligned(self):
        '''Test a 32-bit aligned byte load via a constrained c0'''
        self.assertRegisterEqual(self.MIPS.a1, 0x44, "32-bit aligned lbu returned incorrect value")

    @attr('capabilities')
    def test_cp2_lbu_16aligned(self):
        '''Test a 16-bit aligned byte load via a constrained c0'''
        self.assertRegisterEqual(self.MIPS.a2, 0x66, "16-bit aligned lbu returned incorrect value")

    @attr('capabilities')
    def test_cp2_lbu_8aligned(self):
        '''Test a 8-bit aligned byte load via a constrained c0'''
        self.assertRegisterEqual(self.MIPS.a3, 0x77, "8-bit aligned lbu returned incorrect value")
