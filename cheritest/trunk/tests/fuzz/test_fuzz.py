#-
# Copyright (c) 2011 Robert M. Norton
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

# A nose test which returns a generator to iterate over fuzz test cases.
# Performs a test for every .s file in the TEST_DIR which matches TEST_FILE_RE.
# Compare the log files from gxemul and bluesim to check that the registers
# ended up the same.

import tools.gxemul, tools.sim
import os, re, itertools

# Parameters from the environment
# Cached or uncached mode.
CACHED = bool(int(os.environ.get("CACHED", "0")))
# Pass to restrict to only a particular test
ONLY_TEST = os.environ.get("ONLY_TEST", None)

TEST_FILE_RE=re.compile('test_fuzz_\w+_\d+.s')
TEST_DIR ='tests/fuzz'

#Not derived from unittest.testcase because we wish test_fuzz to
#return a generator.
class TestFuzz(object):
    def test_fuzz(self):
        if ONLY_TEST:
            yield ('check_answer', ONLY_TEST)
        else:
            for test in itertools.ifilter(lambda f: TEST_FILE_RE.match(f) ,os.listdir(TEST_DIR)):
                test_name=os.path.splitext(os.path.basename(test))[0]
                yield ('check_answer', test_name)
                
    def check_answer(self, test_name):
        if CACHED:
            cached="_cached"
        else:
            cached=""
        sim_log = open(os.path.join("log",test_name+cached+".log"), 'rt')
        sim_status=tools.sim.MipsStatus(sim_log)

        gxemul_log = open(os.path.join("gxemul_log", test_name + '_gxemul' +cached + ".log"), 'rt')
        gxemul_status= tools.gxemul.MipsStatus(gxemul_log)
        
        for reg in xrange(len(tools.gxemul.MIPS_REG_NUM2NAME)):
            assert sim_status[reg] == gxemul_status[reg], "%s: (sim) 0x%016x != 0x%016x (gxemul) " % (tools.gxemul.MIPS_REG_NUM2NAME[reg], sim_status[reg], gxemul_status[reg])
