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
# Check basic behaviour of cgetperm and candperm.
#

class test_cp2_getandperm_user(BaseBERITestCase):

    @attr('capabilities')
    def test_cp2_getperm_1(self):
        '''Test that CGetPerm returns correct initial value'''
        self.assertRegisterAllPermissions(self.MIPS.a0, "CGetPerm returns incorrect initial value")

    @attr('capabilities')
    @attr('cap_perm_31')
    def test_cp2_getperm_2(self):
        '''Test that CGetPerm returns correct value after CAndPerm'''
        self.assertRegisterEqual(self.MIPS.a1, 0x40000001, "CGetPerm returns incorrect value after CAndPerm")

    @attr('capabilities')
    @attr('cap_perm_23')
    def test_cp2_getperm_3(self):
        '''Test that CGetPerm returns correct value after CAndPerm'''
        self.assertRegisterEqual(self.MIPS.a2, 0x400001, "CGetPerm returns incorrect value after CAndPerm")

    @attr('capabilities')
    def test_cp2_getperm_4(self):
        '''Test that CGetperm returns correct value after CAndperm'''
        self.assertRegisterEqual(self.MIPS.a3, 0x40001, "CGetperm returns incorrect value after CAndperm")

