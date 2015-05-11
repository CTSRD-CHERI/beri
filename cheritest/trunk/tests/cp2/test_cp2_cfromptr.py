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

#
# Test cfromptr with a non-NULL pointer.
#

class test_cp2_cfromptr(BaseBERITestCase):

    @attr('capabilities')
    def test_cp2_cfromptr_perm(self):
        '''Test that cfromptr of a NULL pointer clears the permissions field'''
        self.assertRegisterEqual(self.MIPS.a0, 0x7fffffff, "cfromptr did not clear the permissions field")

    @attr('capabilities')
    def test_cp2_cfromptr_length(self):
        '''Test that cfromptr of a non-NULL pointer sets the length field'''
        self.assertRegisterEqual(self.MIPS.a2, 0xfffffffffffffffb, "cfromptr did not set the length field correctly")

    @attr('capabilities')
    def test_cp2_cfromptr_type(self):
        '''Test that cfromptr of a non-NULL pointer sets the type field'''
        self.assertRegisterEqual(self.MIPS.a3, 0, "cfromptr did not set the type field correctly")

    @attr('capabilities')
    def test_cp2_cfromptr_tag(self):
        '''Test that cfromptr of a non-NULL pointer sets the tag bit'''
        self.assertRegisterEqual(self.MIPS.a4, 1, "cfromptr did not set the tag bit")

    @attr('capabilities')
    def test_cp2_cfromptr_unsealed(self):
        '''Test that cfromptr of a non-NULL pointer sets the unsealed bit'''
        self.assertRegisterEqual(self.MIPS.a5, 1, "cfromptr did not set the unsealed bit")

