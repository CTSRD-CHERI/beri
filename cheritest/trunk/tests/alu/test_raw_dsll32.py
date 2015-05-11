#-
# Copyright (c) 2011 William M. Morland
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

class test_raw_dsll32(BaseBERITestCase):
        def test_a1(self):
		'''Test a DSLL32 of zero, effective 32'''
		self.assertRegisterEqual(self.MIPS.a0, 0xfedcba9876543210, "Initial value from dli failed to load")
		self.assertRegisterEqual(self.MIPS.a1, 0x7654321000000000, "Shift of thirty-two failed")

	def test_a2(self):
		'''Test a DSLL32 of one, effective 33'''
		self.assertRegisterEqual(self.MIPS.a2, 0xeca8642000000000, "Shift of thirty-three failed")

	def test_a3(self):
		'''Test a DSLL32 of sixteen, effective 48'''
		self.assertRegisterEqual(self.MIPS.a3, 0x3210000000000000, "Shift of fourty-eight failed")

	def test_a4(self):
		'''Test a DSLL32 of 31(max), effective 63'''
		self.assertRegisterEqual(self.MIPS.a4, 0x0000000000000000, "Shift of sixty-three (max) failed")
