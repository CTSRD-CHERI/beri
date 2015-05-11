#-
# Copyright (c) 2012 Jonathan Woodruff
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

class test_tlb_read(BaseBERITestCase):

    @attr('tlb')
    def test_tlb_read_page_mask(self):
        self.assertRegisterEqual(self.MIPS.a0, 0x0, "TLB read of the page mask is incorrect.")

    @attr('tlb')
    def test_tlb_read_index(self):
        self.assertRegisterEqual(self.MIPS.a1, 0x6, "Index value is unexpected after TLB read.")

    @attr('tlb')
    def test_tlb_read_entryHi(self):
        self.assertRegisterEqual(self.MIPS.a2, 0xc000000000002005, "TLB read of EntryHi is incorrect.")

    @attr('tlb')
    def test_tlb_read_entryLo0(self):
        self.assertRegisterEqual(self.MIPS.a3, 0x3017, "TLB read of EntryLo0 is incorrect.")

    @attr('tlb')
    def test_tlb_read_entryLo1(self):
        self.assertRegisterEqual(self.MIPS.a4, 0x4011, "TLB read of EntryLo1 is incorrect.")
