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
# Test that the RDHWR instruction can be used to read the user local register.
# RDHWR is a MIPS32r2 instruction, so this test is not expected to pass on
# earlier MIPS revisions.
# The user local register is not required by MIPS32r2, so this test is not
# expected to work on CPUs that don't implement user local.
#

class test_cp0_userlocal(BaseBERITestCase):

    @attr('rdhwr')
    @attr('userlocal')
    def test_cp0_userlocal_1(self):
        '''Test that the user local register can be written as CP0 reg 4 sel 2 and read as hardware register 29'''
        self.assertRegisterEqual(self.MIPS.a0, 0x123456789abcdef0, "rdhwr did not read back the expected value from the user local register")

