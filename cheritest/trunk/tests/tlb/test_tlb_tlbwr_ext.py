#-
# Copyright (c) 2014 Michael Roe
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

class test_tlb_tlbwr_ext(BaseBERITestCase):

    @attr('tlb')
    @attr('extendedtlb')
    def test_tlb_tlbwr_ext_1(self):
        '''Check the size of the extended TLB'''
        self.assertRegisterEqual(self.MIPS.a0, 0x90, "Extended TLB was not found or did not have the expected number of entries")

    @attr('tlb')
    @attr('extendedtlb')
    def test_tlb_tlbwr_ext_2(self):
        '''Test that the TLB entry for virtual page 1 was written at index 128'''
        self.assertRegisterEqual(self.MIPS.a4, 129, "TLB entry for page 1 was not written at index 129")

    @attr('tlb')
    @attr('extendedtlb')
    def test_tlb_tlbwr_ext_3(self):
        '''Test that the TLB entry for page 129 was written at page 129'''
        self.assertRegisterEqual(self.MIPS.a5, 129, "TLB entry for page 129 was not written at index 129")

    # This test depends on the TLB having the same size and PRNG as BERI1
    @attr('tlb')
    @attr('beri1tlb')
    @attr('deterministic_random')
    def test_tlb_tlbwr_ext_4(self):
        '''Test that the TLB entry for page 1 was evicted to index 13'''
        self.assertRegisterEqual(self.MIPS.a6, 13, "TLB entry for page 1 was not evicted to index 13")

    # This test depends on the TLB having the same size and PRNG as BERI1
    @attr('tlb')
    @attr('beri1tlb')
    @attr('deterministic_random')
    def test_tlb_tlbwr_ext_5(self):
        '''Test that the TLB entry for page 129 was evicted to index 12'''
        self.assertRegisterEqual(self.MIPS.t3, 12, "TLB entry for page 129 was not evicted to index 12")
