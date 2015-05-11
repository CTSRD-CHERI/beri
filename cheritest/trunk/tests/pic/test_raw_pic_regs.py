#-
# Copyright (c) 2014 Jonathan Woodruff
# All rights reserved.
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

class test_raw_pic_regs(BaseBERITestCase):

    @attr('pic')
    def test_pic_control_initial(self):
        self.assertRegisterEqual(self.MIPS.s0, 0x5, "Control registers initialized incorrectly")

    @attr('pic')
    def test_pic_read_initial(self):
        self.assertRegisterEqual(self.MIPS.s1, 0x0, "Read registers initialized incorrectly")
        
    @attr('pic')
    def test_pic_set(self):
        self.assertRegisterEqual(self.MIPS.s2, 0x01, "Set interrupt")

    @attr('pic')
    def test_pic_clear(self):
        self.assertRegisterEqual(self.MIPS.s3, 0x0, "Cleared interrupt")
