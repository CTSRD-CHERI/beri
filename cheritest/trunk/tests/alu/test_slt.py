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

class test_slt(BaseBERITestCase):
    def test_eq(self):
        '''set on less than: equal, non-negative'''
        self.assertRegisterEqual(self.MIPS.a0, 0, "slt returned true for equal, non-negative")

    def test_gt(self):
        '''set on less than: greater than, non-negative'''
        self.assertRegisterEqual(self.MIPS.a1, 0, "slt returned true for great than, non-negative")

    def test_lt(self):
        '''set on less than: less than, non-negative'''
        self.assertRegisterEqual(self.MIPS.a2, 1, "slt returned true for less than, non-negative")

    def test_eq_sign(self):
        '''set on less than: equal, negative'''
        self.assertRegisterEqual(self.MIPS.a3, 0, "slt returned true for equal, negative")

    def test_gt_sign(self):
        '''set on less than: greater than, non-negative'''
        self.assertRegisterEqual(self.MIPS.a4, 0, "slt returned true for greater than, negative")

    def test_lt_sign(self):
        '''set on less than: less than, non-negative'''
        self.assertRegisterEqual(self.MIPS.a5, 1, "slt returned true for less than, negative")

    def test_lt_64bit(self):
        '''set on less than: less than, 64-bit'''
        self.assertRegisterEqual(self.MIPS.a6, 1, "slt returned true for less than, negative")
