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

class test_cp2_x_jr_imprecise(BaseBERITestCase):

    @attr('capabilities')
    @attr('cap_imprecise')
    def test_cp2_x_jr_imprecise_offset_imprecise(self):
        '''Test that EPCC.offset is set to the vaddr of the branch target'''
        self.assertRegisterEqual(self.MIPS.a0, 0x100000000, "EPCC.offset was not set to the expected value after JR out of range of PCC")

    @attr('capabilities')
    @attr('cap_precise')
    def test_cp2_x_jr_imprecise_offset_precise(self):
        '''Test that EPCC.offset is set to branch target when JR out of range'''
        self.assertRegisterEqual(self.MIPS.a1, 0x100000000, "EPCC.offset was not set to the expected value after JR out of range of PCC")

    @attr('capabilities')
    def test_cp2_x_jr_imprecise_exception(self):
        '''Test that an exception is raised when JR outside the range of PCC'''
        self.assertRegisterEqual(self.MIPS.a2, 1, "An exception was not raised after JR out of range of PCC")

    @attr('capabilities')
    @attr('cap_precise')
    def test_cp2_x_jr_imprecise_tag_precise(self):
        '''Test that EPCC.tag is set (precise capabilities'''
        self.assertRegisterEqual(self.MIPS.a4, 1, "EPCC.tag was not set to true after jr out of range of PCC")

    @attr('capabilities')
    @attr('cap_imprecise')
    def test_cp2_x_jr_imprecise_tag_imprecise(self):
        '''Test that EPCC.tag is cleared when EPCC loses precision''' 
        self.assertRegisterEqual(self.MIPS.a4, 0, "EPCC.tag was not cleared after jr out of range of PCC causes PCC to lose precision")
