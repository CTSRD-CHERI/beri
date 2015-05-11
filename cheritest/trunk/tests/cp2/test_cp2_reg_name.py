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

#
# Check that the assembler, simulator, and test suite agree (adequately) on
# the naming of capability registers.
#
# XXXRW: Once we support aliases such as $c2_pcc, we should also check those.
#

class test_cp2_reg_name(BaseBERITestCase):

    # Don't check pcc.offset: it should be equal to the program counter,
    # but the test framework dumps them to the log at different times, so
    # the log will capture different values of PC in PC versus PCC.

    @attr('capabilities')
    def test_cp2_reg_name_c0(self):
        self.assertRegisterEqual(self.MIPS.c0.offset, 0, "CP2 C0 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c1(self):
        self.assertRegisterEqual(self.MIPS.c1.offset, 2, "CP2 C1 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c2(self):
        self.assertRegisterEqual(self.MIPS.c2.offset, 3, "CP2 C2 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c3(self):
        self.assertRegisterEqual(self.MIPS.c3.offset, 4, "CP2 C3 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c4(self):
        self.assertRegisterEqual(self.MIPS.c4.offset, 5, "CP2 C4 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c5(self):
        self.assertRegisterEqual(self.MIPS.c5.offset, 6, "CP2 C5 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c6(self):
        self.assertRegisterEqual(self.MIPS.c6.offset, 7, "CP2 C6 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c7(self):
        self.assertRegisterEqual(self.MIPS.c7.offset, 8, "CP2 C7 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c8(self):
        self.assertRegisterEqual(self.MIPS.c8.offset, 9, "CP2 C8 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c9(self):
        self.assertRegisterEqual(self.MIPS.c9.offset, 10, "CP2 C9 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c10(self):
        self.assertRegisterEqual(self.MIPS.c10.offset, 11, "CP2 C10 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c11(self):
        self.assertRegisterEqual(self.MIPS.c11.offset, 12, "CP2 C11 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c12(self):
        self.assertRegisterEqual(self.MIPS.c12.offset, 13, "CP2 C12 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c13(self):
        self.assertRegisterEqual(self.MIPS.c13.offset, 14, "CP2 C13 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c14(self):
        self.assertRegisterEqual(self.MIPS.c14.offset, 15, "CP2 C14 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c15(self):
        self.assertRegisterEqual(self.MIPS.c15.offset, 16, "CP2 C15 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c16(self):
        self.assertRegisterEqual(self.MIPS.c16.offset, 17, "CP2 C16 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c17(self):
        self.assertRegisterEqual(self.MIPS.c17.offset, 18, "CP2 C17 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c18(self):
        self.assertRegisterEqual(self.MIPS.c18.offset, 19, "CP2 C18 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c19(self):
        self.assertRegisterEqual(self.MIPS.c19.offset, 20, "CP2 C19 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c20(self):
        self.assertRegisterEqual(self.MIPS.c20.offset, 21, "CP2 C20 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c21(self):
        self.assertRegisterEqual(self.MIPS.c21.offset, 22, "CP2 C21 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c22(self):
        self.assertRegisterEqual(self.MIPS.c22.offset, 23, "CP2 C22 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c23(self):
        self.assertRegisterEqual(self.MIPS.c23.offset, 24, "CP2 C23 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c24(self):
        self.assertRegisterEqual(self.MIPS.c24.offset, 25, "CP2 C24 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c25(self):
        self.assertRegisterEqual(self.MIPS.c25.offset, 26, "CP2 C25 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c26(self):
        self.assertRegisterEqual(self.MIPS.c26.offset, 27, "CP2 C26 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c27(self):
        self.assertRegisterEqual(self.MIPS.c27.offset, 28, "CP2 C27 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c28(self):
        self.assertRegisterEqual(self.MIPS.c28.offset, 29, "CP2 C28 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c29(self):
        self.assertRegisterEqual(self.MIPS.c29.offset, 30, "CP2 C29 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c30(self):
        self.assertRegisterEqual(self.MIPS.c30.offset, 31, "CP2 C30 name mismatch")

    @attr('capabilities')
    def test_cp2_reg_name_c31(self):
        self.assertRegisterEqual(self.MIPS.c31.offset, 32, "CP2 C31 name mismatch")
