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

class test_raw_fpu_mul_ps(BaseBERITestCase):

    @attr('floatpaired')
    def test_mul_paired(self):
        '''Test we can multiply paired singles'''
        self.assertRegisterInRange(self.MIPS.s2, 0x4140000043674C07, 0x4140000043674C08, "Failed paired single multiply.")

    @attr('floatpaired')
    @attr('floatpairedrounding')
    def test_mul_paired_rounding(self):
        '''Test we can multiply paired singles, and check rounding'''
        self.assertRegisterEqual(self.MIPS.s2, 0x4140000043674C08, "Failed paired single multiply (checking rounding).")

    @attr('floatpaired')
    def test_mul_paired_qnan(self):
        '''Test paired single multiplication when one of the pair is QNaN'''
        self.assertRegisterEqual(self.MIPS.s3, 0x7F81000040800000, "mul.ps failed to echo QNaN")
