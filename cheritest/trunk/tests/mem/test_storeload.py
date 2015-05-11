#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2012 Robert M. Norton
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

class test_storeload(BaseBERITestCase):
    def test_initial_value1(self):
        self.assertRegisterEqual(self.MIPS.a2, 0x5656565656565656, "Unexpected initial data value.")
    def test_initial_value2(self):
        self.assertRegisterEqual(self.MIPS.a3, 0x5656565656565656, "Unexpected initial data value.")
    def test_initial_value3(self):
        self.assertRegisterEqual(self.MIPS.a4, 0x5656565656565656, "Unexpected initial data value.")

    def test_returned1(self):
        self.assertRegisterEqual(self.MIPS.a5, 0xfeedbeefdeadbeef , "Load following store did not retrieve correct value. ")

    def test_returned2(self):
        self.assertRegisterEqual(self.MIPS.a6, 0xfeedbeefdeadbeef , "Load following store did not retrieve correct value. ")

    def test_returned3(self):
        self.assertRegisterEqual(self.MIPS.a7, 0xfeedbeefdeadbeef , "Load following store did not retrieve correct value. ")
