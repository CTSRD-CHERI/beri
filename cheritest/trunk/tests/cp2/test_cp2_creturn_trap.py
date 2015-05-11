#-
# Copyright (c) 2013 Michael Roe
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
# Test that the CReturn instruction causes a trap to the CCall exception handler
#

class test_cp2_creturn_trap(BaseBERITestCase):

    @attr('capabilities')
    def test_cp2_creturn1(self):
        '''Test that creturn causes a trap'''
        self.assertRegisterEqual(self.MIPS.a2, 2,
            "creturn did not cause the right trap handler to be run")

    @attr('capabilities')
    def test_cp_creturn2(self):
        '''Test that creturn sets the cap cause register'''
        self.assertRegisterEqual(self.MIPS.a3, 0x06ff,
            "creturn did not set capability cause correctly")

    @attr('capabilities')
    def test_cp_creturn3(self):
        '''Test that $kcc is copied to $pcc when trap handler runs'''
        self.assertRegisterEqual(self.MIPS.a4, 0x7fffffff,
            "$pcc was not set to $kcc on entry to trap handler")

    @attr('capabilities')
    def test_cp_creturn4(self):
        '''Test that creturn restored full perms to $pcc'''
        self.assertRegisterEqual(self.MIPS.a6, 0x7fffffff,
            "creturn did not restore full perms to $pcc")


