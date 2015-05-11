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
# Test that cunseal raises a C2E exception if the capability isn't sealed
#

class test_cp2_x_cunseal_unsealed(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_x_cunseal_unsealed_1(self):
        '''Test cunseal did not unseal an already unsealed capability'''
        self.assertRegisterEqual(self.MIPS.a0, 1,
            "cunseal unsealed an already unsealed capability")

    @attr('capabilities')
    def test_cp2_x_cunseal_unsealed_2(self):
        '''Test cunseal raises an exception when capability already unsealed'''
        self.assertRegisterEqual(self.MIPS.a2, 1,
            "cunseal did not raise an exception when capability was already unsealed")

    @attr('capabilities')
    def test_cp2_x_cunseal_unsealed_3(self):
        '''Test capability cause was set correcly when capability was already unsealed'''
        self.assertRegisterEqual(self.MIPS.a3, 0x0302,
            "Capability cause was not set correcly when capability was already unsealed")

