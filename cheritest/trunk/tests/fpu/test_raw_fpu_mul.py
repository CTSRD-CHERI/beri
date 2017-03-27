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

class test_raw_fpu_mul(BaseBERITestCase):

    def test_mul_single(self):
        '''Test we can multiply in single precision'''
        self.assertRegisterEqual(self.MIPS.s1, 0x41800000, "Failed to multiply 4.0 and 4.0 in single precision")

    def test_mul_single_denorm(self):
        '''Test that mul.s flushes a denormalized result to zero'''
        self.assertRegisterEqual(self.MIPS.s4, 0x0, "mul.s failed to flush denormalised result")

    @attr('float64')
    def test_mul_double(self):
        '''Test we can multiply in double precision'''
        self.assertRegisterEqual(self.MIPS.s0, 0x4010000000000000, "Failed to multiply 2.0 and 2.0 in double precision")

    @attr('float64')
    def test_mul_double_2(self):
        '''Test we can multiply -0.276510*0.274042 in double precision'''
        self.assertRegisterEqual(self.MIPS.a0, 0xbfb366026f2c13a9, "MUL.D of -0.276510*0.274042 gave incorrect result")

