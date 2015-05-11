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
# Test csbr (store byte via capability, offset by register) with a privileged
# capability.
#

class test_cp2_csbr_priv(BaseBERITestCase):
    @attr('capabilities')
    def test_cp2_csbr_underflow(self):
        '''Test that csbr did not write below target address'''
        self.assertRegisterEqual(self.MIPS.a0, 0x0, "csbr underflow with privileged capability")

    @attr('capabilities')
    def test_cp2_csbr_data(self):
        '''Test that csbr wrote correctly via privileged capability'''
        self.assertRegisterEqual(self.MIPS.a1, 0x0123456789abcdef, "csbr data written incorrectly with privileged capability")

    @attr('capabilities')
    def test_cp2_csbr_overflow(self):
        '''Test that csbr did not write above target address'''
        self.assertRegisterEqual(self.MIPS.a2, 0x0, "csbr overflow with privileged capability")
