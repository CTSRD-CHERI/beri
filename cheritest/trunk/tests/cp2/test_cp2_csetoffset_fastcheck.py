#-
# Copyright (c) 2015, 2016 Michael Roe
# Copyright (c) 2017 Robert M. Norton
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

@attr('capabilities')
class test_cp2_csetoffset_fastcheck(BaseBERITestCase):
    @attr('cap_precise')
    def test_upper_tag_precise(self):
        self.assertRegisterEqual(self.MIPS.a0, 0x1, "Tag unexpectedly cleared by csetoffset into upper representable hazard zone")

    @attr('cap_precise')
    def test_upper_offset_precise(self):
        self.assertRegisterEqual(self.MIPS.a1, 0xFEFFF0, "Incorrect offset when set into upper representable hazard zone")

    @attr('cap_precise')
    def test_upper_base_precise(self):
        self.assertRegisterEqual(self.MIPS.a2, 0x10000000200000, "Incorrect base when offset set into upper representable hazard zone")

    @attr('cap_imprecise')
    def test_upper_tag_imprecise(self):
        self.assertRegisterEqual(self.MIPS.a0, 0x0, "Tag unexpectedly NOT cleared by csetoffset into upper representable hazard zone")

    @attr('cap_imprecise')
    def test_upper_offset_imprecise(self):
        self.assertRegisterEqual(self.MIPS.a1, 0x100000011efff0, "Incorrect offset when set into upper representable hazard zone")

    @attr('cap_imprecise')
    def test_upper_base_imprecise(self):
        self.assertRegisterEqual(self.MIPS.a2, 0x0, "Incorrect base when offset set into upper representable hazard zone")

###############################################################
# This one is expected to be the same for precise and imprecise

    def test_lower_tag1(self):
        self.assertRegisterEqual(self.MIPS.a3, 0x1, "Tag unexpectedly cleared by csetoffset into lower representable hazard zone")

    def test_lower_offset1(self):
        self.assertRegisterEqual(self.MIPS.a4, 0xffffffffffff0001, "Incorrect offset when set into lower representable hazard zone")

    def test_lower_base1(self):
        self.assertRegisterEqual(self.MIPS.a5, 0x10000000200000, "Incorrect base when offset set into lower representable hazard zone")

###############################################################
# This one is expected to be the same for precise and imprecise

    def test_lower_tag2(self):
        self.assertRegisterEqual(self.MIPS.a6, 0x1, "Tag unexpectedly cleared by csetoffset into lower representable hazard zone")

    def test_lower_offset2(self):
        self.assertRegisterEqual(self.MIPS.a7, 0xffffffffffff0002, "Incorrect offset when set into lower representable hazard zone")

    def test_lower_base2(self):
        self.assertRegisterEqual(self.MIPS.s0, 0x10000000200000, "Incorrect base when offset set into lower representable hazard zone")

###############################################################
# This one can fail with fast check

    @attr('cap_precise')
    def test_lower_tag_precise3(self):
        self.assertRegisterEqual(self.MIPS.s1, 0x1, "Tag unexpectedly cleared by csetoffset into lower representable hazard zone")

    @attr('cap_precise')
    def test_lower_offset_precise3(self):
        self.assertRegisterEqual(self.MIPS.s2, 0xffffffffffff0001, "Incorrect offset when set into lower representable hazard zone")

    @attr('cap_precise')
    def test_lower_base_precise3(self):
        self.assertRegisterEqual(self.MIPS.s3, 0x10000000200000, "Incorrect base when offset set into lower representable hazard zone")

    @attr('cap_imprecise')
    def test_lower_tag_imprecise3(self):
        self.assertRegisterEqual(self.MIPS.s1, 0x0, "Tag unexpectedly NOT cleared by csetoffset into lower representable hazard zone")

    @attr('cap_imprecise')
    def test_lower_offset_imprecise3(self):
        self.assertRegisterEqual(self.MIPS.s2, 0x00100000001f0001, "Incorrect offset when set into lower representable hazard zone")

    @attr('cap_imprecise')
    def test_lower_base_imprecise3(self):
        self.assertRegisterEqual(self.MIPS.s3, 0x0, "Incorrect base when offset set into lower representable hazard zone")
