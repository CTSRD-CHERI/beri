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
# Test what happens when csetbounds raises a C2E exception in a branch delay slot
#

class test_cp2_x_csetbounds_delay2(BaseBERITestCase):

    # XXX : FIXME : This is wrong.
    @attr('capabilities')
    def test_cp2_x_csetbounds_delay2_1(self):
        '''Test CSetBounds did not set the length of of a sealed capability'''
        self.assertRegisterEqual(self.MIPS.a0, 0,
            "CSetBounds set the length of a sealed capability")

    @attr('capabilities')
    def test_cp2_x_csetbounds_delay2_2(self):
        '''Test CSetBounds raised a C2E exception when capability was sealed'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "CSetBounds did not raise an exception when capability was sealed")

    @attr('capabilities')
    def test_cp2_x_csetbounds_delay2_3(self):
        '''Test CP0 cause is set correctly when C2E in a branch delay slot'''
        self.assertRegisterEqual(self.MIPS.a3, 0xffffffff80000048,
            "CP0 cause was not set correcly when C2E in a branch delay slot")

