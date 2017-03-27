#-
# Copyright (c) 2015 Michael Roe
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

class test_cp2_x_cjr_delay(BaseBERITestCase):

    @attr('capabilities')
    def test_cp2_x_cjr_delay_1(self):
        self.assertRegisterEqual(self.MIPS.a2, 1, "Exception in the branch delay slot of CJR did not cause the exception handler to be run")


    @attr('capabilities')
    def test_cp2_x_cjr_delay_2(self):
        self.assertRegisterMaskEqual(self.MIPS.a3, 0x1f << 2, 0x12 << 2, "CP0.Cause.ExcCode was not set correctly by an exception in the branch delay slot of CJR")

    @attr('capabilities')
    def test_cp2_x_cjr_delay_3(self):
        self.assertRegisterMaskEqual(self.MIPS.a3, 0x1 << 31, 0x1 << 31, "CP0.Cause.BD was not set correctly by an exception in the branch delay slot of CJR")
