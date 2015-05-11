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

class test_llsc(BaseBERITestCase):

    @attr('llsc')
    @attr('cached')
    def test_ll_sc_success(self):
	'''That an uninterrupted ll+sc succeeds'''
        self.assertRegisterEqual(self.MIPS.a0, 1, "Uninterrupted ll+sc failed")

    @attr('llsc')
    @attr('cached')
    def test_ll_sc_value(self):
	'''That an uninterrupted ll+sc stored the right value'''
	self.assertRegisterEqual(self.MIPS.a1, 0xffffffff, "Uninterrupted ll+sc stored wrong value")

    @attr('llsc')
    @attr('cached')
    def test_ll_add_sc_success(self):
	'''That an uninterrupted ll+add+sc succeeds'''
	self.assertRegisterEqual(self.MIPS.a3, 1, "Uninterrupted ll+add+sc failed")

    @attr('llsc')
    @attr('cached')
    def test_ll_add_sc_value(self):
	'''That an uninterrupted ll+add+sc stored the right value'''
	self.assertRegisterEqual(self.MIPS.a4, 0, "Uninterrupted ll+add+sc stored wrong value")

    @attr('llsc')
    @attr('cached')
    def test_ll_tnei_sc_failure(self):
	'''That an ll+sc spanning a trap fails'''
	self.assertRegisterEqual(self.MIPS.a7, 0, "Interrupted ll+tnei+sc succeeded")
