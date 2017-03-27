#-
# Copyright (c) 2015, 2016 Michael Roe
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

class test_cp2_fast_rep_check(BaseBERITestCase):
    @attr('capabilities')
    @attr('cap_precise')
    def test_cp2_fast_rep_check_tag_posinc_lower_precise(self):
        self.assertRegisterEqual(self.MIPS.a0, 0x1, "Tag unexpectedly cleared by cincoffset with positive increment near lower representable boundary using precise capabilities")

    @attr('capabilities')
    @attr('cap_precise')
    def test_cp2_fast_rep_check_tag_zeroinc_lower_precise(self):
        self.assertRegisterEqual(self.MIPS.a2, 0x1, "Tag unexpectedly cleared by cincoffset with zero increment near lower representable boundary using precise capabilities")

    @attr('capabilities')
    @attr('cap_precise')
    def test_cp2_fast_rep_check_tag_neginc_lower_precise(self):
                self.assertRegisterEqual(self.MIPS.a4, 0x1, "Tag unexpectedly cleared by cincoffset with negative increment near lower representable boundary using precise capabilities")

    @attr('capabilities')
    @attr('cap_imprecise')
    def test_cp2_fast_rep_check_tag_posinc_lower_imprecise(self):
        self.assertRegisterEqual(self.MIPS.a0, 0x1, "Tag unexpectedly cleared by cincoffset with positive increment near lower representable boundary using imprecise capabilities")

    @attr('capabilities')
    @attr('cap_imprecise')
    def test_cp2_fast_rep_check_tag_zeroinc_lower_imprecise(self):
        self.assertRegisterEqual(self.MIPS.a2, 0x1, "Tag unexpectedly cleared by cincoffset with zero increment near lower representable boundary using imprecise capabilities")

    @attr('capabilities')
    @attr('cap_imprecise')
    def test_cp2_fast_rep_check_tag_neginc_lower_imprecise(self):
                self.assertRegisterEqual(self.MIPS.a4, 0x0, "Tag unexpectedly NOT cleared by cincoffset with negative increment near lower representable boundary using imprecise capabilities")

    @attr('capabilities')
    @attr('cap_precise')
    def test_cp2_fast_rep_check_posinc_upper_precise(self):
        self.assertRegisterEqual(self.MIPS.a6, 0x1, "Tag unexpectedly cleared by cincoffset with positive increment near upper representable boundary using precise capabilities")

    @attr('capabilities')
    @attr('cap_precise')
    def test_cp2_fast_rep_check_zeroinc_upper_precise(self):
        self.assertRegisterEqual(self.MIPS.s0, 0x1, "Tag unexpectedly cleared by cincoffset with zero increment near upper representable boundary using precise capabilities")

    @attr('capabilities')
    @attr('cap_precise')
    def test_cp2_fast_rep_check_neginc_upper_precise(self):
                self.assertRegisterEqual(self.MIPS.s2, 0x1, "Tag unexpectedly cleared by cincoffset with negative increment near upper representable boundary using precise capabilities")

    @attr('capabilities')
    @attr('cap_imprecise')
    def test_cp2_fast_rep_check_posinc_upper_imprecise(self):
        self.assertRegisterEqual(self.MIPS.a6, 0x0, "Tag unexpectedly NOT cleared by cincoffset with positive increment near upper representable boundary using imprecise capabilities")

    @attr('capabilities')
    @attr('cap_imprecise')
    def test_cp2_fast_rep_check_zeroinc_upper_imprecise(self):
        self.assertRegisterEqual(self.MIPS.s0, 0x0, "Tag unexpectedly NOT cleared by cincoffset with zero increment near upper representable boundary using imprecise capabilities")

    @attr('capabilities')
    @attr('cap_imprecise')
    def test_cp2_fast_rep_check_neginc_upper_imprecise(self):
                self.assertRegisterEqual(self.MIPS.s2, 0x1, "Tag unexpectedly cleared by cincoffset with negative increment near upper representable boundary using imprecise capabilities")
