#-
# Copyright (c) 2015 Robert M. Norton
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
# Test clearregs of hi16 cap. registers
#

def initial_regval(x):
    ret = 0
    for bit in range(0, 64, 8):
        ret |= x << bit
    return ret



class test_cp2_clearregs_caphi(BaseBERITestCase):
    @attr('capabilities')
    def test_gp(self):
        '''Test that gp registers have expected values'''
        special_gp_regs = (25, 26, 29, 30, 31)
        for reg in range(32):
            regval = self.MIPS[reg]
            if reg in special_gp_regs:
                pass # skip regs which have other purposes in the test framework
            else:
                # all other registers should have their original value
                self.assertRegisterEqual(regval, initial_regval(reg), "reg $%d modified unexpectedly" % reg)

    @attr('capabilities')
    def test_cap(self):
        '''Test that cap regs have expected values'''
        for reg in range(32):
            capreg_val = getattr(self.MIPS, 'c%d' % reg)
            if reg in (18, 22):
                # we set a couple of regs to check that 'set after clear' works
                # $c0 is special so we don't touch it
                self.assertDefaultCap(capreg_val, "$c%d did not retain set value after clear" % reg)
            elif (reg & 1) == 0 and reg >= 16:
                # the test clears the even numbered registers in gplo16
                self.assertNullCap(capreg_val, "$c%d was not cleared" % reg)
            else:
                self.assertDefaultCap(capreg_val, "$c%d was modified unexpectedly" % reg)
