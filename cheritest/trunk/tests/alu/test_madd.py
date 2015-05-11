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

class test_madd(BaseBERITestCase):
	def test_zero(self):
		'''Test that hi and lo are zeroed'''
		self.assertRegisterEqual(self.MIPS.a0, 0, "Hi was not zeroed")
		self.assertRegisterEqual(self.MIPS.a1, 0, "Lo was not zeroed")

	def test_madd_zeroed(self):
		'''Test of MADD into zeroed hi and lo registers'''
		self.assertRegisterEqual(self.MIPS.a2, 0xffffffffff1d3b59, "Hi was incorrect or not properly sign extended")
		self.assertRegisterEqual(self.MIPS.a3, 0x6a4c2e10, "Lo was incorrect")

	def test_madd_pos(self):
		'''Test MADD of a positive result'''
		self.assertRegisterEqual(self.MIPS.a4, 0xffffffffff1d3b59, "Hi was changed incorrectly")
		self.assertRegisterEqual(self.MIPS.a5, 0x6a4c3827, "An incorrect amount was added to lo")

	def test_pos_neg(self):
		'''Test MADD of a negative result'''
		self.assertRegisterEqual(self.MIPS.a6, 0xffffffffff1d3ad9, "An incorrect amount was subtracted from hi")
		self.assertRegisterEqual(self.MIPS.a7, 0x6a4c3827, "Lo was changed incorrectly")
		
	def test_mult_madd(self):
		'''Test MADD immediately following a MULT'''
		self.assertRegisterEqual(self.MIPS.s1, 2048, "MADD following MULT directly gave the wrong result in Lo.")
		self.assertRegisterEqual(self.MIPS.s0, 0, "MADD following MULT directly gave the wrong result in Hi.")
