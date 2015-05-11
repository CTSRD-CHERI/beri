#-
# Copyright (c) 2014 Robert M. Norton
# All rights reserved.
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

@attr('mt')
class test_ipc(BaseBERITestCase):
    def test_cause_t0(self):
        self.assertRegisterEqual(self.MIPS.threads[0].s0 & 0xffff, 0x800, "Thread 0 cause register not interrupt on IP3")

    def test_epc_t0(self):
        expected_epc=self.MIPS.threads[0].s2
        self.assertRegisterInRange(self.MIPS.threads[0].s1, expected_epc, expected_epc + 4, "Thread 0 epc register not expected_epc")

    def test_cause_t1(self):
        self.assertRegisterEqual(self.MIPS.threads[1].s0 & 0xffff, 0x400, "Thread 1 cause register not interrupt on IP2")

    def test_epc_t1(self):
        expected_epc=self.MIPS.threads[0].s3
        self.assertRegisterInRange(self.MIPS.threads[1].s1, expected_epc, expected_epc + 4, "Thread 1 epc register not expected_epc")
