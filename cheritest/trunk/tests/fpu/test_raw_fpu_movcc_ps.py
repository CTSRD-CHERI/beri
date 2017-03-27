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

class test_raw_fpu_movcc_ps(BaseBERITestCase):

    @attr('floatcmove')
    @attr('floatpaired')
    def test_raw_fpu_movcc_ps_1(self):
        '''Test MOVF.PS (True)'''
        self.assertRegisterEqual(self.MIPS.a0, 0x4100000040000000, "MOVF.PS (True) failed");

    @attr('floatcmove')
    @attr('floatpaired')
    def test_raw_fpu_movcc_ps_2(self):
        '''Test MOVT.PS (False)'''
        self.assertRegisterEqual(self.MIPS.a1, 0x0, "MOVT.PS (False) failed");

    @attr('floatcmove')
    @attr('floatpaired')
    def test_raw_fpu_movcc_ps_3(self):
        '''Test MOVF.PS (False)'''
        self.assertRegisterEqual(self.MIPS.a2, 0x0, "MOVF.PS (False) failed");

    @attr('floatcmove')
    @attr('floatpaired')
    def test_raw_fpu_movcc_ps_4(self):
        '''Test MOVT.PS (True)'''
        self.assertRegisterEqual(self.MIPS.a3, 0x4100000040000000, "MOVT.PS (True) failed");

