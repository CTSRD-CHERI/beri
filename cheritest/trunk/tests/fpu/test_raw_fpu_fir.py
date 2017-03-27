#-
# Copyright (c) 2015 Michael Roe
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

class test_raw_fpu_fir(BaseBERITestCase):

    # On BERI, Revision, ProcessorID and Impl are set to zero

    @attr('floatfirextended')
    def test_fir_s(self):
        '''Test FIR.S'''
        self.assertRegisterMaskEqual(self.MIPS.a0, 1 << 16, 1 << 16, "S (single precision) bit was not set in FIR")

    @attr('floatfirextended')
    def test_fir_d(self):
        '''Test FIR.D'''
        self.assertRegisterMaskEqual(self.MIPS.a0, 1 << 17, 1 << 17, "D (double precision) bit was not set in FIR")

    @attr('floatpaired')
    @attr('floatfirextended')
    def test_fir_ps(self):
        '''Test FIR.PS'''
        self.assertRegisterMaskEqual(self.MIPS.a0, 1 << 18, 1 << 18, "PS (paired single precision) bit was not set in FIR")

    @attr('floatfirextended')
    def test_fir_w(self):
        '''Test FIR.W'''
        self.assertRegisterMaskEqual(self.MIPS.a0, 1 << 20, 1 << 20, "W (word fixed point) bit was not set in FIR")

    @attr('floatfirextended')
    def test_fir_l(self):
        '''Test FIR.L'''
        self.assertRegisterMaskEqual(self.MIPS.a0, 1 << 21, 1 << 21, "L (double word fixed point) bit was not set in FIR")

    @attr('float64')
    @attr('floatfirextended')
    def test_fir_fp64(self):
        '''Test FIR.FP64'''
        self.assertRegisterMaskEqual(self.MIPS.a0, 1 << 22, 1 << 22, "FP64 (64 bit FP registers) bit was not set in FIR") 
