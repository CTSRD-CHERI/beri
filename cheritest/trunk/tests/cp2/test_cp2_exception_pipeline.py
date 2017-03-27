#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2011 Robert M. Norton
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
# Rather complex test to check that EPCC/PCC swapping in exceptions is being
# properly implemented by CP2.  The test runs initially with a privileged PCC,
# then traps, a limited PCC is installed, traps again, and the original PCC is
# restored.  Various bits of evidence are collected along the way, all of
# which we try to check here.
#


class test_cp2_exception_pipeline(BaseBERITestCase):

    @attr('capabilities')
    def test_csetbounds(self):
        '''Test that a syscall flushed CSetBounds from the pipeline.'''
        # Should be unchanged from default
        self.assertRegisterEqual(self.MIPS.c2.length, 0xffffffffffffffff, "CSetBounds instruction was not properly flushed from pipeline")

    @attr('capabilities')
    def test_candperms(self):
        '''Test that a syscall flushed CAndPerms from the pipeline.'''
        # Should be unchanged from default
        self.assertRegisterAllPermissions(self.MIPS.c4.perms, "CAndPerms instruction was not properly flushed from pipeline")

    @attr('capabilities')
    def test_csetoffset(self):
        '''Test that a syscall flushed CSetOffset from the pipeline.'''
        # Should be unchanged from default
        self.assertRegisterEqual(self.MIPS.c5.offset, 0x0, "CSetOffset instruction was not properly flushed from pipeline")

    @attr('capabilities')
    def test_cscr(self):
        '''Test that a syscall flushed CSCR from the pipeline.'''
        # These registers should contain test data, NOT the stored capability register
        self.assertRegisterEqual(self.MIPS.a0, 0xfeedbeefdeadbeef, "CSCR instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.a1, 0xfeedbeefdeadbeef, "CSCR instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.a2, 0xfeedbeefdeadbeef, "CSCR instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.a3, 0xfeedbeefdeadbeef, "CSCR instruction was not properly flushed from pipeline")

    @attr('capabilities')
    def test_clcr(self):
        '''Test that a syscall flushed CLCR from the pipeline.'''
        # The c7 register should be unchanged from its default value
        self.assertRegisterEqual(self.MIPS.c7.ctype, 0, "CLCR instruction was not properly flushed from pipeline")
        self.assertRegisterAllPermissions(self.MIPS.c7.perms, "CLCR instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.c7.offset, 0, "CLCR instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.c7.base, 0, "CLCR instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.c7.length, 0xffffffffffffffff, "CLCR instruction was not properly flushed from pipeline")
