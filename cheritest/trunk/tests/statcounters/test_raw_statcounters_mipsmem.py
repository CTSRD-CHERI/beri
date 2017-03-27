#-
# Copyright (c) 2015-2017 Alexandre Joannou
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

class test_raw_statcounters_mipsmem(BaseBERITestCase):

    @attr('statcounters')
    def test_raw_statcounters_byte_read(self):
        '''Test that querying the byte read counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.a0, 154, "mips mem byte read counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_byte_write(self):
        '''Test that querying the byte write counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.a1, 154, "mips mem byte write counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_hword_read(self):
        '''Test that querying the hword read counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.a2, 36, "mips mem hword read counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_hword_write(self):
        '''Test that querying the hword write counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.a3, 36, "mips mem hword write counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_word_read(self):
        '''Test that querying the word read counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.a4, 222, "mips mem word read counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_word_write(self):
        '''Test that querying the word write counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.a5, 222, "mips mem word write counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_dword_read(self):
        '''Test that querying the dword read counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.a6, 144, "mips mem dword read counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_dword_write(self):
        '''Test that querying the dword write counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.a7, 144, "mips mem dword write counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_cap_read(self):
        '''Test that querying the cap read counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.t0, 24, "mips mem cap read counter corrupted")

    @attr('statcounters')
    def test_raw_statcounters_cap_write(self):
        '''Test that querying the cap write counter returns expected value'''
        self.assertRegisterEqual(self.MIPS.t1, 24, "mips mem cap write counter corrupted")
