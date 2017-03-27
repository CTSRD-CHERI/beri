#-
# Copyright (c) 2014 Michael Roe
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

class test_maddu(BaseBERITestCase):

    @attr('madd')
    def test_maddu_1(self):
	'''Test high word of maddu result, positive argument'''
        self.assertRegisterEqual(self.MIPS.a0, 0, "maddu gave incorrect result")

    @attr('madd')
    def test_maddu_2(self):
	'''Test low word of maddu result, positive argument'''
        self.assertRegisterEqual(self.MIPS.a1, 6, "maddu gave incorrect result")

    @attr('madd')
    def test_maddu_3(self):
        '''Test high word of maddu result, negative argument'''
        self.assertRegisterEqual(self.MIPS.a2, 2, "maddu gave incorrect result")

    @attr('madd')
    def test_maddu_4(self):
        '''Test low word of maddu result, negative argument'''
        self.assertRegisterEqual(self.MIPS.a3, 4, "maddu gave incorrect result")

