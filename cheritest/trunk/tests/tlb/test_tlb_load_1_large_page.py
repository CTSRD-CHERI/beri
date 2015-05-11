#-
# Copyright (c) 2012 Robert M. Norton
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

class test_tlb_load_1_large_page(BaseBERITestCase):
    @attr('tlb')
    @attr('largepage')
    def test_load_succeeded(self):
        self.assertRegisterEqual(self.MIPS.a4, 0xba9876543210fead, "Initial load from large page at 8k failed.")
        self.assertRegisterEqual(self.MIPS.a5, 0xba9876543210fead, "Second load from large page at 8k failed.")
        self.assertRegisterEqual(self.MIPS.a6, 0xfedcba9876543210, "Initial load from large page at 4k failed.")
        self.assertRegisterEqual(self.MIPS.a7, 0xfedcba9876543210, "Second load from large page at 4k failed.")
