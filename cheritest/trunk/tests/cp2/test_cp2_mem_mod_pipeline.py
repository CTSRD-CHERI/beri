#-
# Copyright (c) 2011 Robert N. M. Watson
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
# Test for pipeline forwarding problems between memory loads and input to
# capability modify operations.
#

class test_cp2_mem_mod_pipeline(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_mem_cincoffset(self):
        '''Test that cincoffset uses ld results in pipeline'''
        self.assertRegisterEqual(self.MIPS.a0, 0x100, "cgetoffset returns incorrect value")

    @attr('capabilities')
    def test_cp2_mem_csetbounds(self):
	'''Test that csetbounds uses ld results in pipeline'''
	self.assertRegisterEqual(self.MIPS.a1, 0x100, "cgetlen returns incorrect value")

    @attr('capabilities')
    def test_cp2_mem_candperm(self):
        '''Test that candperm uses ld results in pipeline'''
        self.assertRegisterEqual(self.MIPS.a2, 0xffff & 0x100, "cgetperm returns incorrect value")

    @attr('capabilities')
    def test_cp2_mem_csetoffset(self):
        '''Test that csetoffset uses ld results in pipeline'''
        self.assertRegisterEqual(self.MIPS.a3, 0x100, "cgetoffset returns incorrect value")
