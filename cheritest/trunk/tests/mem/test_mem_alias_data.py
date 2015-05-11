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

class test_mem_alias_data(BaseBERITestCase):
    def test_expected_values(self):
        v0=0x0001020304050607
        v1=0x1011121314151617
        v2=0x2021222324252627
        self.assertRegisterEqual(self.MIPS.a3, v0, "a3 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.a4, v1, "a4 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.a5, v0, "a5 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.a6, v1, "a6 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.a7, v2, "a7 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.s0, v0, "s0 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.s1, v1, "s1 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.s2, v1, "s2 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.s3, v2, "s3 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.s4, v2, "s4 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.s5, 0,  "s5 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.s6, 0,  "s6 did not have correct value.")
        self.assertRegisterEqual(self.MIPS.s7, v0, "s7 did not have correct value.")

   
   
   
   
   
   
   
   
   
   
   
   
