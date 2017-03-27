#-
# Copyright (c) 2011 William M. Morland
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

class test_madd_lo_overflow(BaseBERITestCase):

    @attr('madd')
    def test_initial(self):
        '''Test that lo is full'''
        self.assertRegisterEqual(self.MIPS.a0, 0, "Hi is incorrect")
        self.assertRegisterEqual(self.MIPS.a1, 0xffffffffffffffff, "Lo is not full")

    @attr('madd')
    def test_madd_zeroed(self):
        '''Test that the bits correctly overflow from lo into hi'''
        self.assertRegisterEqual(self.MIPS.a2, 1, "Hi was incorrect")
        self.assertRegisterEqual(self.MIPS.a3, 0, "Lo was incorrect")
