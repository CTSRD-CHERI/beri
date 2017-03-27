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

class test_cp2_cllh(BaseBERITestCase):

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllh_1(self):
	'''That an uninterrupted cllh+csch succeeds'''
        self.assertRegisterEqual(self.MIPS.a0, 1, "Uninterrupted cllh+csch failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllh_2(self):
	'''That an uninterrupted cllh+csch stored the right value'''
	self.assertRegisterEqual(self.MIPS.a1, 0xffffffffffffffff, "Uninterrupted cllh+csch stored wrong value")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllh_4(self):
	'''That an uninterrupted cllh+add+csch succeeds'''
	self.assertRegisterEqual(self.MIPS.a2, 1, "Uninterrupted cllh+add+csch failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllh_5(self):
	'''That an uninterrupted cllh+add+csch stored the right value'''
	self.assertRegisterEqual(self.MIPS.a3, 0, "Uninterrupted cllh+add+csch stored wrong value")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllh_8(self):
	'''That an cllh+csch spanning a trap fails'''
	self.assertRegisterEqual(self.MIPS.a4, 0, "Interrupted cllh+tnei+csch succeeded")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s0(self):
        '''Test signed-extended capability load linked half-word from double word'''
        self.assertRegisterEqual(self.MIPS.s0, 0xfffffffffffffedc, "Sign-extended capability load linked word from double word failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s1(self):
        '''Test signed-extended positive capability load linked half-word'''
        self.assertRegisterEqual(self.MIPS.s1, 0x7fff, "Sign-extended positive half-word capability load linked failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s2(self):
        '''Test signed-extended negative capability load linked half-word'''
        self.assertRegisterEqual(self.MIPS.s2, 0xffffffffffffffff, "Sign-extended negative half-word capability load linked failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s3(self):
        '''Test unsigned positive capability load linked half-word'''
        self.assertRegisterEqual(self.MIPS.s3, 0x7fff, "Unsigned positive half-word capability load linked failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_s4(self):
        '''Test unsigned negative capability load linked half-word'''
        self.assertRegisterEqual(self.MIPS.s4, 0xffff, "Unsigned negative half-word capability load linked failed")
