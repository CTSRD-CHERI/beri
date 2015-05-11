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

class test_raw_swr(BaseBERITestCase):
	def test_a0(self):
		'''Test SWR with zero offset'''
		self.assertRegisterEqual(self.MIPS.a0, 0x9800000000000000, "SWR with zero offset failed")

	def test_a1(self):
		'''Test SWR with full word offset'''
		self.assertRegisterEqual(self.MIPS.a1, 0x9800000098000000, "SWR with full word offset failed")

	def test_a2(self):
		'''Test SWR with half word offset'''
		self.assertRegisterEqual(self.MIPS.a2, 0xdcba980098000000, "SWR with half word offset failed")

	def test_a3(self):
		'''Test SWR with three byte offset'''
		self.assertRegisterEqual(self.MIPS.a3, 0xdcba9800fedcba98, "SWR with three byte offset failed")

	def test_a4(self):
		'''Test SWR with one byte offset'''
		self.assertRegisterEqual(self.MIPS.a4, 0xdcba9800ba98ba98, "SWR with one byte offset failed")
