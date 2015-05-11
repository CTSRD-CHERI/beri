#-
# Copyright (c) 2011 Jonathan Woodruff
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

class test_movz_movn_pipeline(BaseBERITestCase):
    def test_movz_pipeline_true(self):
        '''Test that result of MOVZ test is correct.'''
        self.assertRegisterEqual(self.MIPS.s0, 0xFFFFFFFFFFFFFFFF, "MOVZ moved when it shouldn't have.")
    def test_movz_pipeline_false(self):
        '''Test that result of MOVZ test is correct.'''
        self.assertRegisterEqual(self.MIPS.s1, 0x0000000000000001, "MOVZ did not move when it should have.")
    def test_movn_pipeline_true(self):
        '''Test that result of MOVN test is correct.'''
        self.assertRegisterEqual(self.MIPS.s2, 0xFFFFFFFFFFFFFFFF, "MOVN moved when it shouldn't have.")
    def test_movn_pipeline_false(self):
        '''Test that result of MOVN test is correct.'''
        self.assertRegisterEqual(self.MIPS.s3, 0x0000000000000001, "MOVN did not move when it should have.")
    def test_movn_pipeline_false(self):
        '''Test that result of MOVN test is correct.'''
        self.assertRegisterEqual(self.MIPS.s5, 0xfffffffffffffffc, "MOVZ did not forward correctly in case found in freeBSD.")
