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
# Test that a floating point store clears the tag bit
#

class test_cp2_floatstore(BaseBERITestCase):
    @attr('capabilities')
    @attr('float')
    def test_cp2_floatstore_1(self):
        '''Test that stored float can be read back'''
        self.assertRegisterEqual(self.MIPS.a0, 0x01234567,
            "Floating point load of floating point value returned incorrect result")

    @attr('capabilities')
    @attr('float')
    def test_cp2_floatstore_2(self):
        '''Test FP store followed by integer load'''
        self.assertRegisterEqual(self.MIPS.a1, 0x01234567,
            "Integer load of floating point value returned incorrect result")

    @attr('capabilities')
    @attr('float')
    def test_cp2_floatstore_3(self):
        '''Test that floating point store clears the tag bit'''
        self.assertRegisterEqual(self.MIPS.a2, 0,
            "Floating point store did not clear the tag bit")

