#-
# Copyright (c) 2013 Michael Roe
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

#
# Test floating point division of a small number by itself
#

from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr

class test_fpu_x_disabled(BaseBERITestCase):

    def test_fpu_x_disabled_1(self):
        '''Test that a floating point operation raises an exception if the FPU is disabled'''
	self.assertRegisterEqual(self.MIPS.a2, 1, "A floating point operation with the FPU disabled did not raise an exception")

    def test_fpu_x_disabled_2(self):
        '''Test that CP0.cause.ExcCode is set when FPU is disabled'''
	self.assertRegisterEqual(self.MIPS.a3, 11, "CP0.cause.exccode was not set to coprocessor unusable when the FPU was disabled")

    def test_fpu_x_disabled_3(self):
        '''Test that CP0.cause.ce is set when FPU is disabled'''
	self.assertRegisterEqual(self.MIPS.a4, 1, "CP0.cause.ce was not set to 1 when the FPU was disabled")

