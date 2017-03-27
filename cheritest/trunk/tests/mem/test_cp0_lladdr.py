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

class test_cp0_lladdr(BaseBERITestCase):
    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_reset(self):
	'''Test that CP0 lladdr is 0 on CPU reset'''
	self.assertRegisterEqual(self.MIPS.a0, 0, "CP0 lladdr non-zero on reset");

    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_after_ll(self):
	'''Test that lladdr is set correctly after load linked'''
	self.assertRegisterEqual(self.MIPS.a1, self.MIPS.s0, "lladdr after ll incorrect")

    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_after_sc(self):
	'''Test that lladdr is still set correctly after store conditional'''
	self.assertRegisterEqual(self.MIPS.a2, self.MIPS.s0, "lladdr after sc incorrect")

    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_after_lld(self):
	'''Test that lladdr is set correctly after load linked double word'''
	self.assertRegisterEqual(self.MIPS.a3, self.MIPS.s3, "lladdr after lld incorrect")

    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_after_scd(self):
	'''Test that lladdr is still set correctly after store conditional double word'''
	self.assertRegisterEqual(self.MIPS.a4, self.MIPS.s3, "lladdr after scd incorrect")

    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_double_ll(self):
	'''Test that if a second ll occurs before sc, sc will see the second lladdr'''
	self.assertRegisterEqual(self.MIPS.a5, self.MIPS.s2, "lladdr after double ll incorrect")

    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_double_lld(self):
	'''Test that if a second lld occurs before scd, scd will see the second lladdr'''
	self.assertRegisterEqual(self.MIPS.a6, self.MIPS.s4, "lladdr after double lld incorrect")

    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_ll_interrupted(self):
	'''Test that if an ll is followed by an sw that clears LLbit, lladdr is still correct'''
	self.assertRegisterEqual(self.MIPS.a7, self.MIPS.s2, "lladdr after interrupted ll incorrect")

    @attr('llsc')
    @attr('lladdr')
    @attr('cached')
    def test_lladdr_lld_interrupted(self):
	'''Test that if an lld is followed by an sd that clears LLbit, lladdr is still correct'''
	self.assertRegisterEqual(self.MIPS.s6, self.MIPS.s5, "lladdr after interrupted lld incorrect")
