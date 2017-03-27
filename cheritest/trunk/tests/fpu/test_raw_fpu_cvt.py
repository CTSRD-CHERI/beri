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
from nose.plugins.attrib import attr

class test_raw_fpu_cvt(BaseBERITestCase):
    def test_convert_rounding_mode(self):
        self.assertRegisterMaskEqual(self.MIPS.s7, 0x3, 0, "FP rounding mode is not round to nearest even")

    def test_convert_word_to_single(self):
        '''Test we can convert words to single floating point'''
        self.assertRegisterEqual(self.MIPS.t0, 0x3F800000, "Didn't convert 1 to FP")
        self.assertRegisterEqual(self.MIPS.t1, 0x4C00041A, "Didn't convert non exact to FP")
        self.assertRegisterEqual(self.MIPS.t2, 0xFFFFFFFFC1B80000, "Didn't convert -23 to FP")

    @attr('float64')
    def test_convert_double_to_single(self):
        '''Test we can convert doubles to singles'''
        self.assertRegisterEqual(self.MIPS.s0, 0x3F800000, "Didn't convert 1 from double.")
        self.assertRegisterMaskEqual(self.MIPS.s1, 0xfffffffe, 0x3e2aaaaa, "Didn't convert 1/6 from double.")
        self.assertRegisterMaskEqual(self.MIPS.s1, 0x1, 1, "Didn't round to nearest when converting from double to single.")
        self.assertRegisterEqual(self.MIPS.s2, 0xffffffffc36aa188, "Didn't convert -234.6311 from double")
        self.assertRegisterEqual(self.MIPS.s3, 0x4f0c0473, "Didn't convert large number from double.")

    @attr('float64')
    def test_convert_singles_to_doubles(self):
        '''Test we can convert singles to doubles'''
        self.assertRegisterEqual(self.MIPS.s4, 0x3FF0000000000000, "Didn't convert 1 to double.")
        self.assertRegisterEqual(self.MIPS.s5, 0x3FC99999A0000000, "Didn't conver 0.2 to double.")
        self.assertRegisterEqual(self.MIPS.s6, 0xC0D1DCE8C0000000, "Didn't convert -18291.636 to double")

