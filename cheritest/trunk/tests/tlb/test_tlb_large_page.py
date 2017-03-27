#-
# Copyright (c) 2016 Michael Roe
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

class test_tlb_large_page(BaseBERITestCase):

    @attr('tlb')
    def test_tlb_large_page_1(self):
        self.assertRegisterEqual(self.MIPS.a3, 0x1234, "Load from data segment via TLB large pages returned incorrect result")

    @attr('tlb')
    def test_tlb_large_page_2(self):
        self.assertRegisterEqual(self.MIPS.a4, 0xdead, "Load at offset > 4K via TLB large page returned incorrect result")


    @attr('tlb')
    def test_tlb_large_page_3(self):
        self.assertRegisterEqual(self.MIPS.a5, 0xbeef, "Load at offset > 4M via TLB large page returned incorrect result")

    @attr('tlb')
    def test_tlb_large_page_4(self):
        self.assertRegisterEqual(self.MIPS.a6, 0xf00d, "Load at offset > 8M via TLB large page returned incorrect result")

