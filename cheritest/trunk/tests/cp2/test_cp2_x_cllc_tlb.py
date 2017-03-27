#-
# Copyright (c) 2014 Michael Roe
# Copyright (c) 2014 Robert M. Norton
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

class test_cp2_x_cllc_tlb(BaseBERITestCase):

    @attr('capabilities')
    @attr('tlb')
    def test_cp2_cllc_tlb_base(self):
        '''Test that capability load succeeded when TLB entry prohibited load'''
        self.assertRegisterEqual(self.MIPS.a3, 0x40, "clc did not load c1.base when capbility load inhibit bit was set in the TLB")

    @attr('capabilities')
    @attr('tlb')
    def test_cp2_cllc_tlb_length(self):
        '''Test that capability load succeeded when TLB entry prohibited load'''
        self.assertRegisterEqual(self.MIPS.a4, 0x40, "clc did not load c1.length when capbility load inhibit bit was set in the TLB")

    @attr('capabilities')
    @attr('tlb')
    def test_cp2_cllc_tlb_tag(self):
        '''Test that capability tag was cleared when TLB entry prohibited load'''
        self.assertRegisterEqual(self.MIPS.a6, 0x0, "clc did not clear c1.tag when capbility load inhibit bit was set in the TLB")

    @attr('capabilities')
    @attr('tlb')
    def test_cp2_cllc_tlb_progress(self):
        '''Test that test reaches the end of stage 6'''
        self.assertRegisterEqual(self.MIPS.a5, 6, "Test did not make it to the end of stage 6")

    @attr('capabilities')
    @attr('tlb')
    def test_cp2_cllc_tlb_cause(self):
        '''Test that CP0 cause set to syscall'''
        self.assertRegisterEqual(self.MIPS.a7, 0x8 << 2, "CP0 cause not set to syscall")

    @attr('capabilities')
    @attr('tlb')
    def test_cp2_cllc_tlb_exception_count(self):
        '''Test that only one exception occurred'''
        self.assertRegisterEqual(self.MIPS.a0, 0x1, "Expected exactly one exception")
