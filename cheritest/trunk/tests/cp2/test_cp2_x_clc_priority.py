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
# Test exception priority: C2E/Length Violation has higher priority
# than an address error.
#

class test_cp2_x_clc_priority(BaseBERITestCase):

    @attr('capabilities')
    def test_cp2_x_clc_prority_1(self):
        '''Test clc set cause code to Length Violation'''
        self.assertRegisterEqual(self.MIPS.a3, 0x0101,
            "clc did not set cause code to Length Violation")

    @attr('capabilities')
    def test_cp2_x_clc_prority_2(self):
        '''Test clc set exception cause code to C2E'''
        self.assertRegisterEqual(self.MIPS.a4, 18*4,
            "clc did not set exception cause to C2E")

