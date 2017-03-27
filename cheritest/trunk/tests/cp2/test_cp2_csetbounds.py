#-
# Copyright (c) 2015 Michael Roe
# All rights reserved.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
# project, funded by EPSRC grant EP/K008528/1.
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

class test_cp2_csetbounds(BaseBERITestCase):

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csetbounds_len_exact(self):
        self.assertRegisterEqual(self.MIPS.a0, 4, "CSetBounds did not set the length to the expected value")

    @attr('capabilities')
    def test_cp2_csetbounds_len_inexact(self):
        self.assertRegisterInRange(self.MIPS.a0, 4, 0xffffffffffffffff, "CSetBounds did not set the length within the expected range")


    @attr('capabilities')
    def test_cp2_csetbounds_base_plus_offset(self):
        self.assertRegisterEqual(self.MIPS.a1, 0, "CSetBounds did not set base+offset to the expected value")

    @attr('capabilities')
    @attr('cap256')
    def test_cp2_csetbounds_offset_exact(self):
        self.assertRegisterEqual(self.MIPS.a2, 0, "CSetBounds did not set the base to the expected value")

    @attr('capabilities')
    def test_cp2_csetbounds_offset_inexact(self):
        self.assertRegisterInRange(self.MIPS.a2, 0, 0x7fffffffffffffff, "CSetBounds did not set the offset greater than or equal to the base")
