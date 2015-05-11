#-
# Copyright (c) 2011 William M. Morland
# Copyright (c) 2012 Jonathan Woodruff
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

class test_msub(BaseBERITestCase):
	def test_initial(self):
		'''Test that lo is full'''
		self.assertRegisterEqual(self.MIPS.a0, 0, "Hi is incorrect")
		self.assertRegisterEqual(self.MIPS.a1, 0xffffffffffffffff, "Lo is not full")

	def test_msub_zeroed(self):
		'''Test that the bits correctly overflow from lo into hi'''
		self.assertRegisterEqual(self.MIPS.a2, 1, "Hi was incorrect")
		self.assertRegisterEqual(self.MIPS.a3, 0, "Lo was incorrect")

	def test_msub_pos(self):
		'''Test msub with a positive number'''
		self.assertRegisterEqual(self.MIPS.a4, 0, "Subtraction incorrect")
		self.assertRegisterEqual(self.MIPS.a5, 0xfffffffffffff5e9, "Subtraction incorrect")

	def test_msub_neg(self):
		'''Test msub with a negative number'''
		self.assertRegisterEqual(self.MIPS.a6, 0x80, "Subtraction of negative number incorrect")
		self.assertRegisterEqual(self.MIPS.a7, 0xfffffffffffff5e9, "Lo incorrectly affected by addition in the higher range")
		
	def test_msub_after_mtlo(self):
		'''Test msub following mtlo'''
		self.assertRegisterEqual(self.MIPS.s0, 0, "Multiply subtract immediatly after mtlo had the wrong hi register")
		self.assertRegisterEqual(self.MIPS.s1, 1024, "Multiply subtract immediatly after mtlo had the wrong lo register")
