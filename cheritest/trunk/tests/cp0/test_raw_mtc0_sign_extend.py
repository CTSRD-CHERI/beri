#-
# Copyright (c) 2011 William M. Morland
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

class test_raw_mtc0_sign_extend(BaseBERITestCase):

    def test_mtc0_lui(self):
        '''Test we can load a negative 32-bit value into $a0'''
        self.assertRegisterEqual(self.MIPS.a0, 0x00000000ffff0000, "LUI instruction failed")

    @attr('mtc0signex')
    def test_mtc0_signext(self):
        '''MTC0 should sign extend (some documentation suggests all 64-bits should be copied but sign-extension is logical and in line with other operations and GXemul)'''
        self.assertRegisterEqual(self.MIPS.a0|0xffffffff00000000, self.MIPS.a2, "Value not copied in and out of EPC correctly")

    def test_mfc0_signext_mtc0(self):
        self.assertRegisterEqual(self.MIPS.a0|0xffffffff00000000, self.MIPS.a1, "MFC0 did not correctly sign extend")

    def test_dmtc0_nosignext(self):
        self.assertRegisterEqual(self.MIPS.a0, self.MIPS.a4, "Value was altered in process of dmtc0 and dmfc0")

    def test_mfc0_signext_dmtc0(self):
        self.assertRegisterEqual(self.MIPS.a0|0xffffffff00000000, self.MIPS.a3, "MFC0 did not correctly sign extend")


