#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2013 Michael Roe
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

class test_cp2_clld_span(BaseBERITestCase):


    @attr('llsc')
    @attr('llscspan')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_clld_3(self):
	'''That an uninterrupted clld+cld+cscd succeeds'''
	self.assertRegisterEqual(self.MIPS.a0, 1, "Uninterrupted clld+cld+cscd failed")

    @attr('llsc')
    @attr('llscspan')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_clld_7(self):
	'''That an clld+cscd spanning a store to the line does not store'''
	self.assertRegisterNotEqual(self.MIPS.a2, 1, "Interrupted clld+csd+cscd stored value")

    @attr('llsc')
    @attr('llscspan')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_clld_6(self):
	'''That an clld+csd+cscd spanning fails'''
	self.assertRegisterEqual(self.MIPS.t0, 0, "Interrupted clld+csd+cscd succeeded")
