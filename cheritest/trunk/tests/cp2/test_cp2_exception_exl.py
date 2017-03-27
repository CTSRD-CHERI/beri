#-
# Copyright (c) 2015 Michael Roe
# Copyright (c) 2017 Robert M. Norton
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

@attr('capabilities')
@attr('exception_exl')
class test_cp2_exception_exl(BaseBERITestCase):

    def test_cp2_exception_exl_epc(self):
        self.assertRegisterEqual(self.MIPS.a0, 0, "An exception with EXL=1 set EPC when it should not have done.")

    def test_cp2_exception_exl_epcc(self):
        self.assertRegisterEqual(self.MIPS.c1.offset, 0, "An exception with EXL=1 set EPCC when it should not have done.")
        self.assertRegisterEqual(self.MIPS.c1.base, 0, "An exception with EXL=1 set EPCC when it should not have done.")
        self.assertRegisterEqual(self.MIPS.c1.length, 0, "An exception with EXL=1 set EPCC when it should not have done.")
        self.assertRegisterEqual(self.MIPS.c1.t, 0, "An exception with EXL=1 set EPCC when it should not have done.")
