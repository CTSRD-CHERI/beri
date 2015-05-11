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
    def test_cincbase(self):
        # Should be unchanged from default
        self.assertRegisterEqual(self.MIPS.c2.base, 0x0, "cincbase instruction was not properly flushed from pipeline")
    @attr('capabilities')
    def test_csetlen(self):
        # Should be unchanged from default
        self.assertRegisterEqual(self.MIPS.c3.length, 0xffffffffffffffff, "csetlen instruction was not properly flushed from pipeline")
    @attr('capabilities')
    def test_candperms(self):
        # Should be unchanged from default
        self.assertRegisterEqual(self.MIPS.c4.perms, 0x7fffffff, "candperms instruction was not properly flushed from pipeline")
    @attr('capabilities')
    def test_csettype(self):
        # Should be unchanged from default
        self.assertRegisterEqual(self.MIPS.c5.ctype, 0x0, "csettype instruction was not properly flushed from pipeline")
    @attr('capabilities')
    def test_cscr(self):
        # These registers should contain test data, NOT the stored capability register
        self.assertRegisterEqual(self.MIPS.a0, 0xfeedbeefdeadbeef, "cscr instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.a1, 0xfeedbeefdeadbeef, "cscr instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.a2, 0xfeedbeefdeadbeef, "cscr instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.a3, 0xfeedbeefdeadbeef, "cscr instruction was not properly flushed from pipeline")
    @attr('capabilities')
    def test_clcr(self):
        # The c7 register should be unchanged from its default value
        self.assertRegisterEqual(self.MIPS.c7.ctype, 0, "clcr instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.c7.perms, 0x7fffffff, "clcr instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.c7.base, 0, "clcr instruction was not properly flushed from pipeline")
        self.assertRegisterEqual(self.MIPS.c7.length, 0xffffffffffffffff, "clcr instruction was not properly flushed from pipeline")
