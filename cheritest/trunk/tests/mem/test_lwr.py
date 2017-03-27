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

class test_lwr(BaseBERITestCase):

    def test_lwr_0(self):
        self.assertRegisterEqual(self.MIPS.a0, 0xffffffffffffff01, "LWR at offset 0 gave unexpected result")

    def test_lwr_1(self):
        self.assertRegisterEqual(self.MIPS.a1, 0xffffffffffff0102, "LWR at offset 1 gave unexpected result")

    def test_lwr_2(self):
        self.assertRegisterEqual(self.MIPS.a2, 0xffffffffff010203, "LWR at offset 2 gave unexpected result")

    def test_lwr_3(self):
        self.assertRegisterEqual(self.MIPS.a3, 0x0000000001020304, "LWR at offset 2 gave unexpected result")

    def test_lwr_4(self):
        self.assertRegisterEqual(self.MIPS.a5, 0, "LWR at offset increased by 4 gave a different result")