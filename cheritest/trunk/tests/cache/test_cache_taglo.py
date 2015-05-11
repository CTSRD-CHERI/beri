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

class test_cache_taglo(BaseBERITestCase):

    @attr('cache')
    @attr('loadcachetag')
    def test_cache_taglo_1(self):
        '''Test that we can read CP0.TagLo'''
        self.assertRegisterEqual(self.MIPS.a2, 1, "Read of CP0 TagLo did not complete")

    @attr('cache')
    @attr('loadcachetag')
    # In a BERi1-like cache/TLB configuration. DCache line size is 32 bytes
    @attr('beri1cache')
    def test_cache_taglo_2(self):
        '''Test that L1 data cache line size has the expected value'''
        self.assertRegisterEqual(self.MIPS.a3, 32, "L1 data cache line size had an unexpected value")

    @attr('cache')
    @attr('loadcachetag')
    # In a BERi1-like cache/TLB configuration. L2 cache line size is 128 bytes
    @attr('beri1cache')
    def test_cache_taglo_3(self):
        '''Test that L2 cache line size has the expected value'''
        self.assertRegisterEqual(self.MIPS.a4, 128, "L2 cache line size had an unexpected value")
