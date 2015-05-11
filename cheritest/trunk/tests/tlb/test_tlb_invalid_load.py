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

# a0: paddr of testdata
# a1: PFN of testdata
# a2: EntryLo0 value
# a3: EntryLo1 value
# a4: Vaddr of testdata
# a5: Result of load 
# a6: Expected PC of faulting instruction
	
# s0: BadVAddr
# s1: Context
# s2: XContext
# s3: EntryHi
# s4: Status
# s5: Cause
# s6: EPC	

class test_tlb_invalid_load(BaseBERITestCase):

    @attr('tlb')
    def test_badvaddr(self):
        self.assertRegisterEqual(self.MIPS.s0, self.MIPS.a4, "Wrong BadVaddr")

    @attr('tlb')
    def test_context(self):
        self.assertRegisterEqual(self.MIPS.s1, (self.MIPS.a4 & 0xffffe000)>>9, "Wrong Context") # TODO test page table base

    @attr('tlb')
    def test_xcontext(self):
        self.assertRegisterEqual(self.MIPS.s2, (self.MIPS.a4 & 0xffffe000)>>9, "Wrong XContext") # TODO test page table base

    @attr('tlb')
    def test_entryhi(self):
        self.assertRegisterEqual(self.MIPS.s3, self.MIPS.a4 & 0xfffff000, "Wrong EntryHi")

    @attr('tlb')
    def test_status(self):
        self.assertRegisterEqual(self.MIPS.s4 & 2, 2, "Wrong EXL")

    @attr('tlb')
    def test_cause(self):
        self.assertRegisterEqual(self.MIPS.s5 & 0x7c, 0x8, "Wrong Exception Code")

    @attr('tlb')
    def test_epc(self):
        '''Test EPC after TLB Invalid exception'''
        self.assertRegisterEqual(self.MIPS.a6, self.MIPS.s6, "Wrong EPC")
