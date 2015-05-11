#-
# Copyright (c) 2012 Ben Thorner
# Copyright (c) 2013 Colin Rothwell
# Copyright (c) 2013 Michael Roe
# All rights reserved.
#
# This software was developed by Ben Thorner as part of his summer internship
# and Colin Rothwell as part of his final year undergraduate project.
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

class test_raw_fpu_cvt_s_w(BaseBERITestCase):

    def test_raw_fpu_cvt_s_w_1(self):
        '''Test we can convert 1 (32 bit int) to single precision'''
        self.assertRegisterEqual(self.MIPS.a0, 0x3F800000, "Didn't convert 1 (32 bit int) to single precision")

    def test_raw_fpu_cvt_s_w_2(self):
        '''Test we can convert 0x4c00041a (32 bit int) to single precision'''
        self.assertRegisterEqual(self.MIPS.a1, 0x4C00041A, "Didn't convert non exact to single precision")

    def test_raw_fpu_cvt_s_w_3(self):
        '''Test we can convert -23 (32 bit int) to single precision'''
        self.assertRegisterEqual(self.MIPS.a2, 0xFFFFFFFFC1B80000, "Didn't convert -23 to single precision")

    def test_raw_fpu_cvt_s_w_4(self):
        '''Test we can convert 0 (32 bit int) to single precision'''
        self.assertRegisterEqual(self.MIPS.a3, 0, "Didn't convert 0 to single precision")

