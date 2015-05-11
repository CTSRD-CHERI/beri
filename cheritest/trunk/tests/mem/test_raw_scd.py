#-
# Copyright (c) 2011 Steven J. Murdoch
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

class test_raw_scd(BaseBERITestCase):
    @attr('llsc')
    def test_store(self):
        '''Store conditional of word to double word'''
        self.assertRegisterEqual(self.MIPS.a0, 1, "Store conditional of word to double word failed")

    @attr('llsc')
    def test_load(self):
        '''Load of conditionally stored word from double word'''
        self.assertRegisterEqual(self.MIPS.a1, 0xfedcba9876543210, "Load of conditionally stored word from double word failed")

    @attr('llsc')
    def test_store_positive(self):
        '''Store conditional of positive word'''
        self.assertRegisterEqual(self.MIPS.a2, 1, "Store conditional of positive word failed")

    @attr('llsc')
    def test_load_positive(self):
        '''Load of conditionally stored positive word'''
        self.assertRegisterEqual(self.MIPS.a3, 1, "Load of conditionally stored positive word failed")

    @attr('llsc')
    def test_store_negative(self):
        '''Store conditional of negative word'''
        self.assertRegisterEqual(self.MIPS.a4, 1, "Store conditional of negative word failed")

    @attr('llsc')
    def test_load_negative(self):
        '''Load of conditionally stored negative word'''
        self.assertRegisterEqual(self.MIPS.a5, 0xffffffffffffffff, "Load of conditionally stored negative word failed")

    @attr('llsc')
    def test_store_pos_offset(self):
        '''Store conditional of word at positive offset'''
        self.assertRegisterEqual(self.MIPS.a6, 1, "Store conditional of word at positive offset failed")

    @attr('llsc')
    def test_load_pos_offset(self):
        '''Load of conditionally stored word from positive offset'''
        self.assertRegisterEqual(self.MIPS.a7, 2, "Load of conditionally stored word at positive offset failed")

    @attr('llsc')
    def test_store_neg_offset(self):
        '''Store conditional of word at negative offset'''
        self.assertRegisterEqual(self.MIPS.s0, 1, "Store conditional of word at negative offset failed")

    @attr('llsc')
    def test_load_neg_offset(self):
        '''Load of conditionally stored word from negative offset'''
        self.assertRegisterEqual(self.MIPS.s1, 1, "Load of conditionally stored word at negative offset failed")
        
    @attr('llsc')
    @attr('llscnotmatching')
    def test_store_load_linked_not_matching(self):
        '''Store conditional of word which should fail due to unmatching load linked address'''
        self.assertRegisterEqual(self.MIPS.s2, 0, "Store conditional of word to a different address than the link register succeeded")

    @attr('llsc')
    @attr('llscnotmatching')
    def test_load_load_linked_not_matching(self):
        '''Load after store conditional which should have failed due to unmatching load linked address'''
        self.assertRegisterEqual(self.MIPS.s3, 0xfedcba9876543210, "Store conditional with unmatching load linked address wrote to memory")
