#-
# Copyright (c) 2012 Michael Roe
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
# Test that lb raises a C2E exception if c0.tag is not set.
#

class test_cp2_x_lb_tag(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_x_lb_tag_1(self):
        '''Test lb did not read when c0.tag was not set'''
        self.assertRegisterEqual(self.MIPS.a0, 0,
            "lb read when c0.tag was not set")

    @attr('capabilities')
    def test_cp2_x_lb_tag_2(self):
        '''Test lb raises an exception when c0.tag is not set'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "lb did not raise an exception when c0.tag was not set")

    @attr('capabilities')
    def test_cp2_x_lb_tag_3(self):
        '''Test lb sets capability cause correctly when c0.tag is not set'''
        self.assertRegisterEqual(self.MIPS.a3, 0x0200,
            "Capability cause was not set correctly when c0.tag was not set")

