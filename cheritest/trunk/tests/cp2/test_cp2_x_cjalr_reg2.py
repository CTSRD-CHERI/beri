#-
# Copyright (c) 2012, 2015 Michael Roe
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
# Test that cjalr raises an exception if don't have permission for a 
# reserved register.
#

class test_cp2_x_cjalr_reg2(BaseBERITestCase):

    @attr('capabilities')
    def test_cp2_x_cjalr_reg2_1(self):
        '''Test CJALR did not jump when did not have permission for register'''
        self.assertRegisterEqual(self.MIPS.a0, 0,
            "CJALR jumped when did not have permission for register")

    @attr('capabilities')
    def test_cp2_x_cjalr_reg2_2(self):
        '''Test CJALR raised an exception did not have permission for register'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "CJALR did not raise an exception when did not permission for register")

    @attr('capabilities')
    def test_cp2_x_cjalr_reg2_3(self):
        '''Test CJALR set capability cause when did not have permission for register'''
        self.assertRegisterEqual(self.MIPS.a3, 0x181b,
            "CJALR did not set capability cause correctly when did not have permission for register")

