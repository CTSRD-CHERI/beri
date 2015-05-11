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
# Test that loading a capability after store to memory works.
#

class test_cp2_clcr(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_clcr_getperm(self):
        '''Test that clcr loaded perms fields correctly'''
        self.assertRegisterEqual(self.MIPS.a0, 0x7fffffff, "clcr read back incorrect perms")

    @attr('capabilities')
    def test_cp2_clcr_getoffset(self):
        '''Test that clcr loaded the offset field correctly'''
        self.assertRegisterEqual(self.MIPS.a1, 0x0000000000000001, "clcr loaded incorrect offset")

    @attr('capabilities')
    def test_cp2_clcr_getbase(self):
        '''Test that clcr loaded the base field correctly'''
        self.assertRegisterEqual(self.MIPS.a2, 0x0000000000000000, "clcr loaded incorrect base address")

    @attr('capabilities')
    def test_cp2_clcr_getlen(self):
        '''Test that clcr loaded the length field correctly'''
        self.assertRegisterEqual(self.MIPS.a3, 0xffffffffffffffff, "clcr loaded incorrect length")
        
    @attr('capabilities')
    def test_cp2_clcr_gettag(self):
        '''Test that clcr loaded the tag correctly'''
        self.assertRegisterEqual(self.MIPS.a4, 0x0000000000000001, "clcr load has the correct tag")
