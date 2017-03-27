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

class test_cp2_cllc(BaseBERITestCase):

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllc_1(self):
	'''That an uninterrupted cllc+cscc succeeds'''
        self.assertRegisterEqual(self.MIPS.a1, 1, "Uninterrupted cllc+cscc failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllc_2(self):
	'''That an uninterrupted cllc+cscc stored untagged'''
	self.assertRegisterEqual(self.MIPS.a5, 0, "Uninterrupted cllc+cscc stored tag")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllc_3(self):
	'''That an uninterrupted cllc+csetoffset+cscc succeeds'''
	self.assertRegisterEqual(self.MIPS.a2, 1, "Uninterrupted cllc+csetoffset+cscc failed")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllc_4(self):
	'''That an uninterrupted cllc+csetoffset+cscc stored the right offset'''
	self.assertRegisterEqual(self.MIPS.a0, self.MIPS.c4.offset, "Uninterrupted cllc+csetoffset+cscc stored the wrong offset")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllc_5(self):
	'''That an uninterrupted cllc+csetoffset+cscc wrote a tag'''
	self.assertRegisterEqual(self.MIPS.a6, 1,  "Uninterrupted cllc+csetoffset+cscc failed to store a tag")

    @attr('llsc')
    @attr('cached')
    @attr('capabilities')
    def test_cp2_cllc_8(self):
	'''That an cllc+cscc spanning a trap fails'''
	self.assertRegisterEqual(self.MIPS.a4, 0, "Interrupted cllc+tnei+cscc succeeded")
