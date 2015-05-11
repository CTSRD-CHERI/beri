#-
# Copyright (c) 2012 Ben Thorner
# Copyright (c) 2013 Colin Rothwell
# All rights reserved.
#
# This software was developed by Ben Thorner as part of his summer internship
# and Colin Rothwell as part of his final year undergraduate project.
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

class test_raw_fpu_sw_lw(BaseBERITestCase):
    def test_positive(self):
        '''Test can save and load positive float'''
        self.assertRegisterEqual(self.MIPS.s1, 0x3f800000, "Failed to save and load 1.0")
        self.assertRegisterEqual(self.MIPS.s2, 0x10101010, "swc1 overwrote word after")
        self.assertRegisterEqual(self.MIPS.s3, 0x20202020, "swc1 overwrote word before")

    def test_negative(self):
        '''Test can save and load negative float'''
        self.assertRegisterEqual(self.MIPS.s4, 0xffffffffbf800000, "Failed to save and load -1")

    def test_offset(self):
        '''Test we can store floats at location offsets.'''
        self.assertRegisterEqual(self.MIPS.s5, 0x41800000, 'Failed to load from offset 8')
        self.assertRegisterEqual(self.MIPS.s6, 0x3D800000, 'Failed to store at offset 8')
