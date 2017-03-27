#-
# Copyright (c) 2013, 2016 Michael Roe
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
# Test that floating point load raises a C2E exception if c0 does not grant
# Permit_Load.
#

class test_cp2_x_ldxc1_perm(BaseBERITestCase):

    @attr('capabilities')
    @attr('float')
    @attr('floatindexed')
    @attr('float64')
    def test_cp2_x_ldxc1_perm_1(self):
        '''Test LDXC1 did not load without Permit_Load permission'''
        self.assertRegisterEqual(self.MIPS.a0, 0,
            "LDXC1 loaded without Permit_Load permission")

    @attr('capabilities')
    @attr('float')
    @attr('floatindexed')
    @attr('float64')
    def test_cp2_x_ldxc1_perm_2(self):
        '''Test LDXC1 raises an exception when doesn't have Permit_Load permission'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "LDXC1 did not raise an exception when didn't have Permit_Load permission")

    @attr('capabilities')
    @attr('float')
    @attr('floatindexed')
    @attr('float64')
    def test_cp2_x_ldxc1_perm_3(self):
        '''Test capability cause is set correctly when doesn't have Permit_Load permission'''
        self.assertRegisterEqual(self.MIPS.a3, 0x1200,
            "Capability cause was not set correctly when didn't have Permit_Load permission")

