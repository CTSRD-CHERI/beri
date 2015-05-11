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

class test_raw_dsllv(BaseBERITestCase):
        def test_a1(self):
		'''Test a DSLLV of zero'''
		self.assertRegisterEqual(self.MIPS.a0, 0xfedcba9876543210, "Initial value from dli failed to load")
		self.assertRegisterEqual(self.MIPS.a1, 0xfedcba9876543210, "Shift of zero failed")

	def test_a2(self):
		'''Test a DSLLV of one'''
		self.assertRegisterEqual(self.MIPS.a2, 0xfdb97530eca86420, "Shift of one failed")

	def test_a3(self):
		'''Test a DSLLV of sixteen'''
		self.assertRegisterEqual(self.MIPS.a3, 0xba98765432100000, "Shift of sixteen failed")

	def test_a4(self):
		'''Test a DSLLV of 32'''
		self.assertRegisterEqual(self.MIPS.a4, 0x7654321000000000, "Shift of thirty-two failed")

	def test_a5(self):
		'''Test a DSLLV of 43'''
		self.assertRegisterEqual(self.MIPS.a5, 0xa190800000000000, "Shift of fourty-three failed")

	def test_a6(self):
		'''Test a DSLLV pf 63(max)'''
		self.assertRegisterEqual(self.MIPS.a6, 0x0000000000000000, "Shift of sixty-three failed")
