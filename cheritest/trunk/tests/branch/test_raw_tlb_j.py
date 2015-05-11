#-
# Copyright (c) 2011 Steven J. Murdoch
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

# Test for a sequence of instructions on Cheri2 that triggered a bug.
# Problem occurs when a branch is already past execute when an exception
# occurs which lands on a branch.

class test_raw_tlb_j(BaseBERITestCase):

    @attr('tlb')
    def test_before_jr(self):
        '''Test that instruction before TLB miss is executed'''
        self.assertRegisterEqual(self.MIPS.a0, 1, "instruction before TLB miss was not executed")

    @attr('tlb')
    def test_after_miss1(self):
        self.assertRegisterEqual(self.MIPS.a1, 0, "instruction after exception executed")

    @attr('tlb')
    def test_after_miss2(self):
        self.assertRegisterEqual(self.MIPS.a2, 0, "instruction after exception executed")

    @attr('tlb')
    def test_after_miss3(self):
        self.assertRegisterEqual(self.MIPS.a3, 0, "instruction after exception executed")

    @attr('tlb')
    def test_jr_target(self):
        '''Test that execute instruction after returning from TLB miss handler'''
        self.assertRegisterEqual(self.MIPS.a4, 5, "instruction at jump target not executed")

    @attr('tlb')
    def test_miss_vector(self):
        self.assertRegisterEqual(self.MIPS.a5, 6, "instruction at miss vector not executed")

    @attr('tlb')
    def test_miss_vector_wrongpath(self):
        self.assertRegisterNotEqual(self.MIPS.a6, 7, "took wrong path in exception vector.")
