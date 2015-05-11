#-
# Copyright (c) 2011 Robert N. M. Watson
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

class test_lldscd_span(BaseBERITestCase):

    @attr('llsc')
    @attr('cached')
    @attr('llscspan')
    def test_lld_ld_scd_success(self):
	'''That lld+ld+scd succeeds'''
	self.assertRegisterEqual(self.MIPS.a2, 1, "lld+ld+scd failed")

    @attr('llsc')
    @attr('cached')
    @attr('llscspan')
    def test_lld_sd_scd_failure(self):
	'''That an lld+sd+scd spanning a store to the line fails'''
	self.assertRegisterEqual(self.MIPS.t0, 0, "Interrupted lld+sd+scd succeeded")

    @attr('llsc')
    @attr('cached')
    @attr('llscspan')
    def test_lld_sd_scd_value(self):
	'''That an lld+scd spanning a store to the line does not store'''
	self.assertRegisterNotEqual(self.MIPS.a6, 1, "Interrupted lld+sd+scd stored value")
