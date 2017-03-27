#-
# Copyright (c) 2015 Michael Roe
# All rights reserved.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
# project, funded by EPSRC grant EP/K008528/1.
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

class test_cp2_cap_as_data(BaseBERITestCase):

    @attr('capabilities')
    def test_cp2_cap_as_data_tag(self):
        '''Test that copying a capability as data clears the tag'''
        self.assertRegisterEqual(self.MIPS.a0, 0, "Copying a capability as data did not clear the tag bit")

    @attr('capabilities')
    @attr('cap_copy_as_data')
    def test_cp2_cap_as_data_perms(self):
        '''Test that copying a capability as data copies permissions'''
        self.assertRegisterEqual(self.MIPS.a1, 0, "Copying a capability as data did not copy the permissions")

    @attr('capabilities')
    @attr('cap_copy_as_data')
    def test_cp2_cap_as_data_base(self):
        '''Test that copying a capability as data copies base'''
        self.assertRegisterEqual(self.MIPS.a2, 0, "Copying a capability as data did not copy the base")

    @attr('capabilities')
    @attr('cap_copy_as_data')
    def test_cp2_cap_as_data_len(self):
        '''Test that copying a capability as data copies length'''
        self.assertRegisterEqual(self.MIPS.a3, 0, "Copying a capability as data did not copy the length")

    # The L3 model of precise capabilities with less than 256 bits preserves
    # the offset, even though it does not have enough space to preserve all
    # the fields. So don't tag 'cap_copy_as_data'.
    @attr('capabilities')
    def test_cp2_cap_as_data_offset(self):
        '''Test that copying a capability as data copies offset'''
        self.assertRegisterEqual(self.MIPS.a4, 0, "Copying a capability as data did not copy the offset")

