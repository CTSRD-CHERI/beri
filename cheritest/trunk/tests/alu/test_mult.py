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

class test_mult(BaseBERITestCase):
	def test_pos_pos(self):
		'''Test of positive number multiplied by positive number'''
		self.assertRegisterEqual(self.MIPS.a0, 0, "Load from hi or mult failed")
		self.assertRegisterEqual(self.MIPS.a1, 0xb88, "Load from lo or mult failed")

	def test_neg_neg(self):
		'''Test of negative number multiplied by negative number'''
		self.assertRegisterEqual(self.MIPS.a2, 0, "Load from hi or mult failed")
		self.assertRegisterEqual(self.MIPS.a3, 0xb88, "Load from lo or mult failed")

	def test_neg_pos(self):
		'''Test of negative number multiplied by positive number'''
		self.assertRegisterEqual(self.MIPS.a4, 0xffffffffffffffff, "Load from hi or mult failed")
		self.assertRegisterEqual(self.MIPS.a5, 0xfffffffffffff478, "Load from lo or mult failed")

	def test_pos_neg(self):
		'''Test of positive number multiplied by negative number'''
		self.assertRegisterEqual(self.MIPS.a6, 0xffffffffffffffff, "Load from hi or mult failed")
		self.assertRegisterEqual(self.MIPS.a7, 0xfffffffffffff478, "Load from lo or mult failed")
