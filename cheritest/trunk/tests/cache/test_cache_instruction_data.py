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

#
# XXX: our test code saves the CP0 config register in self.MIPS.s1 so that
# we can determine how this test should behave.  Our test cases don't
# currently check that, so may return undesired failures.  The third check
# below should be conditioned on (DC > 0) || (SC == 1) -- i.e., a cache is
# present, which might cause it not to incorrectly fire for gxemul.
#

class test_cache_instruction_data(BaseBERITestCase):

    @attr('cache')
    @attr('counterdev')
    def test_initial_uncached_read(self):
        self.assertRegisterEqual(self.MIPS.a0, 0, "Initial read of count register is incorrect")
        
    @attr('cache')
    @attr('counterdev')
    def test_initial_cached_read(self):
        self.assertRegisterEqual(self.MIPS.a1, 1, "Initial cached read failure")
        
    @attr('cache')
    @attr('counterdev')
    def test_second_cached_read(self):
        self.assertRegisterEqual(self.MIPS.a2, 1, "Second cached read failure")
        
    @attr('cache')
    @attr('counterdev')
    def test_after_L1_writeback_cached_read(self):
        self.assertRegisterEqual(self.MIPS.a3, 1, "Cached read after data L1 writeback is incorrect")
        
    @attr('cache')
    @attr('counterdev')
    def test_after_L1_writeback_invalidate_cached_read(self):
        self.assertRegisterEqual(self.MIPS.a4, 1, "Cached read after data L1 writeback/invalidate is incorrect")
        
    @attr('cache')
    @attr('counterdev')
    def test_after_L1_invalidate_cached_read(self):
        self.assertRegisterEqual(self.MIPS.a5, 1, "Cached read after data L1 invalidate is incorrect")
         
    @attr('cache')
    @attr('counterdev')
    def test_after_L1_and_L2_invalidate_cached_read(self):
        self.assertRegisterEqual(self.MIPS.a6, 1, "Cached read after data and L2 invalidate is incorrect")       

    @attr('cache')
    @attr('loadcachetag')
    def test_index_load_tag_dcache(self):
        self.assertRegisterEqual(self.MIPS.a7, 0x000000004001fe00, "Index load tag dCache unexpected value")
