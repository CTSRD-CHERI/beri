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

class test_eret(BaseBERITestCase):
    def test_a0(self):
        '''Confirm EXL was set by test code'''
        self.assertRegisterEqual((self.MIPS.a0 >> 1) & 0x1, 1, "Unable to set EXL")

    def test_a1(self):
        '''Check that instruction before eret ran'''
        self.assertRegisterEqual(self.MIPS.a1, 1, "Instruction before ERET missed")

    def test_a2(self):
        '''Check that instruction after eret didn't run (not a branch-delay!)'''
        self.assertRegisterNotEqual(self.MIPS.a2, 2, "Instruction after ERET ran")

    def test_a3(self):
        '''Check that instruction before EPC target didn't run'''
        self.assertRegisterNotEqual(self.MIPS.a3, 3, "Instruction before EPC target ran")

    def test_a4(self):
        '''Check that instruction after EPC target did run'''
        self.assertRegisterEqual(self.MIPS.a4, 4, "Instruction at EPC target missed")

    def test_a5(self):
        '''Check that eret cleared EXL'''
        self.assertRegisterEqual((self.MIPS.a5 >> 1) & 0x1, 0, "EXL not cleared by eret")
