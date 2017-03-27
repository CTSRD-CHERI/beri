#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2011 Steven J. Murdoch
# Copyright (c) 2013 Michael Roe
# Copyright (c) 2015 SRI International
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

class test_cp2_cllw(BaseBERITestCase):

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllw_1(self):
	'''That an uninterrupted cllw+cscw succeeds'''
        self.assertRegisterEqual(self.MIPS.a0, 1, "Uninterrupted cllw+cscw failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllw_2(self):
	'''That an uninterrupted cllw+cscw stored the right value'''
	self.assertRegisterEqual(self.MIPS.a1, 0xffffffffffffffff, "Uninterrupted cllw+cscw stored wrong value")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllw_4(self):
	'''That an uninterrupted cllw+add+cscw succeeds'''
	self.assertRegisterEqual(self.MIPS.a2, 1, "Uninterrupted cllw+add+cscw failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllw_5(self):
	'''That an uninterrupted cllw+add+cscw stored the right value'''
	self.assertRegisterEqual(self.MIPS.a3, 0, "Uninterrupted cllw+add+cscw stored wrong value")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllw_8(self):
	'''That an cllw+cscw spanning a trap fails'''
	self.assertRegisterEqual(self.MIPS.a4, 0, "Interrupted cllw+tnei+cscw succeeded")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s0(self):
        '''Test signed-extended load linked word from double word'''
        self.assertRegisterEqual(self.MIPS.s0, 0xfffffffffedcba98, "Sign-extended load linked word from double word failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s1(self):
        '''Test signed-extended positive load linked word'''
        self.assertRegisterEqual(self.MIPS.s1, 0x7fffffff, "Sign-extended positive word load linked failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s2(self):
        '''Test signed-extended negative load linked word'''
        self.assertRegisterEqual(self.MIPS.s2, 0xffffffffffffffff, "Sign-extended negative word load linked failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s3(self):
        '''Test unsigned positive load linked word'''
        self.assertRegisterEqual(self.MIPS.s3, 0x7fffffff, "Unsigned positive word load linked failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s4(self):
        '''Test unsigned negative load linked word'''
        self.assertRegisterEqual(self.MIPS.s4, 0xffffffff, "Unsigned negative word load linked failed")
