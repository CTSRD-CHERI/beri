#
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
# Test CBTU (capability branch if tag is unset)
#

class test_cp2_cbtu(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_cbtu_1(self):
        '''Test that cbtu does not branch if the tag is set'''
        self.assertRegisterEqual(self.MIPS.a0, 1,
            "cbtu branched when tag was set")

    @attr('capabilities')
    def test_cp2_cbtu_2(self):
        '''Test that cbtu branches if the tag is not set'''
        self.assertRegisterEqual(self.MIPS.a1, 0,
            "cbtu did not branch when tag was unset")

    @attr('capabilities')
    def test_cp2_cbtu_3(self):
        '''Test that cbtu executes the instruction in the branch delay slot'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "cbtu did not execute instruction in branch delay slot")

