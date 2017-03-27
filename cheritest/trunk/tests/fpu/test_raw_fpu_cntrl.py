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

class test_raw_fpu_cntrl(BaseBERITestCase):

    def test_movc(self):
        '''Test to ensure we can move 32 bits between COP1 and GPR registers'''
        self.assertRegisterEqual(self.MIPS.s0, 9, "MOVC failed")
        
    def test_dmovc(self):
        '''Test to ensure we can move 64 bits between COP1 and GPR registers'''
        self.assertRegisterEqual(self.MIPS.s1, (18 << 32) + 7, "DMOVC failed")
        
    def test_cmov_single(self):
        '''Test to ensure we can move values between FPRs'''
        self.assertRegisterEqual(self.MIPS.t8, 0x41000000, "CMOV failed for single precision")

    @attr('float64')
    def test_cmov_double(self):
        self.assertRegisterEqual(self.MIPS.t3, 0x4000000000000000, "CMOV failed for double precision")

    def test_register_name_collisions(self):
        '''Test that a register name referring to a control register doesn't
        prevent the use of data registers with that name.'''
        self.assertRegisterEqual(self.MIPS.t0, 0xFFFFFFFFDEADBEEF, "Can't use f0")
        self.assertRegisterEqual(self.MIPS.t1, 0xFEED000000000000, "Can't use f25")
        self.assertRegisterEqual(self.MIPS.a1, 0xFFFFABCD00000000, "Can't use f26")
        self.assertRegisterEqual(self.MIPS.a2, 0xFFFFFFFFDEAF0000, "Can't use f28")
        self.assertRegisterEqual(self.MIPS.a3, 0x0000000000004321, "Can't use f31")
