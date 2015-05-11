#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2013 Robert M. Norton
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
# Test to check that using cp2 if it is disabled causes a coprocessor
# unusable exception.
#

class test_cp2_disabled_exception(BaseBERITestCase):

    @attr('capabilities')
    def test_exception_counter(self):
        self.assertRegisterEqual(self.MIPS.a0, 1, "CP2 exception counter not 2")

    @attr('capabilities')
    def test_cause(self):
        cpUnusable = (self.MIPS.a1 >> 28) & 3
        ex = (self.MIPS.a1 >> 2) & 0x1f
        self.assertEqual(cpUnusable, 2, "cp unusable not 2")
        self.assertEqual(ex, 11, "exception cause not 11 (cp unusable)")

    @attr('capabilities')
    def test_epc(self):
        self.assertRegisterEqual(self.MIPS.a2, self.MIPS.a3, "expected epc did not match")
