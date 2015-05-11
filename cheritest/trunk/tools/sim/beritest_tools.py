#!/usr/bin/python
#-
# Copyright (c) 2011 Steven J. Murdoch
# Copyright (c) 2013 Alexandre Joannou
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
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

import unittest
import os
import os.path

from tools.sim import *

def is_envvar_true(var):
    '''Return true iff the environment variable specified is defined and
    not set to "0"'''
    return os.environ.get(var, "0") != "0"

class BaseBERITestCase(unittest.TestCase):
    '''Abstract base class for test cases for the BERI CPU running under BSIM.
    Concrete subclasses may override class variables LOG_DIR (for the location
    of the log directory, defaulting to "log") and LOG_FN (for the name of the
    log file within LOG_DIR, defaulting to the class name appended with
    ".log"). Subclasses will be provided with the class variable MIPS, containing
    an instance of MipsStatus representing the state of the BERI CPU.'''

    LOG_DIR = os.environ.get("LOGDIR", "log")
    LOG_FN = None
    MIPS = None
    MIPS_EXCEPTION = None
    ## Trigger a test failure (for testing the test-cases)
    ALWAYS_FAIL = is_envvar_true("DEBUG_ALWAYS_FAIL")

    @classmethod
    def setUpClass(self):
        '''Parse the log file and instantiate MIPS'''
        self.cached = bool(int(os.environ.get("CACHED", "0")))
        self.multi = bool(int(os.environ.get("MULTI1", "0")))
        if self.LOG_FN is None:
            if self.multi and self.cached:
                self.LOG_FN = self.__name__ + "_cachedmulti.log"
            elif self.multi:
                self.LOG_FN = self.__name__ + "_multi.log"
            elif self.cached:
                self.LOG_FN = self.__name__ + "_cached.log"
            else:
                self.LOG_FN = self.__name__ + ".log"
        fh = open(os.path.join(self.LOG_DIR, self.LOG_FN), "rt")
        try:
            self.MIPS = MipsStatus(fh)
        except MipsException, e:
            self.MIPS_EXCEPTION = e

    def id(self):
        id = unittest.TestCase.id(self)
        if not self.cached:
            return id

        pos = id.find(".")
        assert(pos >= 0)
        return id[:pos] + "_cached" + id[pos:]

    def setUp(self):
        if not self.MIPS_EXCEPTION is None:
            raise self.MIPS_EXCEPTION

    def assertRegisterEqual(self, first, second, msg=None):
        '''Convenience method which outputs the values of first and second if
        they are not equal (preceded by msg, if given)'''
        if self.ALWAYS_FAIL:
            first=1
            second=2
        if first != second:
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "0x%016x != 0x%016x"%(first,second))

    def assertRegisterNotEqual(self, first, second, msg=None):
        '''Convenience method which outputs the values of first and second if
        they are equal (preceded by msg, if given)'''
        if self.ALWAYS_FAIL:
            first=1
            second=1
        if first == second:
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "0x%016x == 0x%016x"%(first,second))

    def assertRegisterExpected(self, reg_num, expected_value, msg=None):
        '''Check that the contents of a register, specified by its number,
        matches the expected value. If the contents do not match, output the
        register name, expected value, and actual value (preceded by msg, if
        given).'''
        if self.ALWAYS_FAIL:
            first=1
            second=2
        else:
            first=self.MIPS[reg_num]
            second=expected_value
        if first != second:
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "0x%016x (%s) != 0x%016x"%(
                first,MIPS_REG_NUM2NAME[reg_num],second))

    def assertRegisterInRange(self, reg_val, expected_min, expected_max, msg=None):
        '''Check that a register value is in a specified inclusive range. If
        not, fails the test case outputing details preceded by msg, if given.'''
        if self.ALWAYS_FAIL:
            expected_min=1
            expected_max=0
        if reg_val < expected_min or reg_val > expected_max:
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "0x%016x is outside of [0x%016x,0x%016x]"%(
                reg_val, expected_min, expected_max))

    def assertRegisterMaskEqual(self, first, mask, second, msg=None):
        '''Convenience method which outputs the values of first and second if
        they are not equal on the bits selected by the mask (preceded by msg,
        if given)'''
        if self.ALWAYS_FAIL:
            first = 1
            second = 2
            mask = 0x3
        if first & mask != second:
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "0x%016x and 0x%016x != 0x%016x"%(first, mask, second))

    def assertRegisterMaskNotEqual(self, first, mask, second, msg=None):
        '''Convenience method which outputs the values of first and second if
        they are equal on the bits selected by the mask (preceded by msg,
        if given)'''
        if self.ALWAYS_FAIL:
            first = 1
            second = 1
            mask = 0x3
        if first & mask == second:
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "0x%016x and 0x%016x == 0x%016x"%(first, mask, second))

class BaseICacheBERITestCase(BaseBERITestCase):
    '''Abstract base class for test cases for the BERI Instruction Cache.'''

    LOG_DIR = os.environ.get("LOGDIR", "log")
    LOG_FN = None
    ICACHE = None
    ICACHE_EXCEPTION = None
    ## Trigger a test failure (for testing the test-cases)
    ALWAYS_FAIL = is_envvar_true("DEBUG_ALWAYS_FAIL")

    @classmethod
    def setUpClass(self):
        '''Parse the log file and instantiate MIPS'''
        super(BaseBERITestCase, self).setUpClass()
        self.cached = bool(int(os.environ.get("CACHED", "0")))
        self.multi = bool(int(os.environ.get("MULTI1", "0")))
        if self.LOG_FN is None:
            if self.multi and self.cached:
                self.LOG_FN = self.__name__ + "_cachedmulti.log"
            elif self.multi:
                self.LOG_FN = self.__name__ + "_multi.log"
            elif self.cached:
                self.LOG_FN = self.__name__ + "_cached.log"
            else:
                self.LOG_FN = self.__name__ + ".log"
        fh = open(os.path.join(self.LOG_DIR, self.LOG_FN), "rt")
        try:
            self.ICACHE = ICacheStatus(fh)
        except ICacheException, e:
            self.ICACHE_EXCEPTION = e

    def setUp(self):
        super(BaseBERITestCase, self).setUp()
        if not self.ICACHE_EXCEPTION is None:
            raise self.ICACHE_EXCEPTION

    def assertTagValid(self, tag_idx, msg=None):
        '''Convenience method which outputs the values of tag it is not valid (preceded by msg, if given)'''
        tag = self.ICACHE[tag_idx]
        if self.ALWAYS_FAIL:
            tag.valid = False
        if (tag.valid == False):
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "tag=>%r"%(tag))

    def assertTagInvalid(self, tag_idx, msg=None):
        '''Convenience method which outputs the values of tag it is valid (preceded by msg, if given)'''
        tag = self.ICACHE[tag_idx]
        if self.ALWAYS_FAIL:
            tag.valid = True
        if (tag.valid == True):
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "tag=>%r"%(tag))

    def assertTagExpectedValue(self, tag_idx, expected_value, msg=None):
        '''Check that the contents of a tag, specified by its number,
        matches the expected value. If the contents do not match, output the
        register name, expected value, and actual value (preceded by msg, if
        given).'''
        tag = self.ICACHE[tag_idx]
        if self.ALWAYS_FAIL:
            tag.valid = False
        if (tag.valid == False or tag.value != expected_value):
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "tag=>%r, expected_value=>%x"%(tag, expected_value))

    def assertTagInRange(self, tag_idx, expected_min, expected_max, msg=None):
        '''Check that a register value is in a specified inclusive range. If
        not, fails the test case outputing details preceded by msg, if given.'''
        tag = self.ICACHE[tag_idx]
        if self.ALWAYS_FAIL:
            expected_min=1
            expected_max=0
        if tag.valid == False or tag.value < expected_min or tag.value > expected_max:
            if msg is None:
                msg = ""
            else:
                msg = msg + ": "
            self.fail(msg + "tag=>%r, range=>[0x%016x,0x%016x]"%(tag, expected_min, expected_max))

def main():
    import sys
    if len(sys.argv) != 2:
        print "Usage: %0 LOGFILE"%sys.argv[0]
    regs = MipsStatus(file(sys.argv[1], "rt"))
    print regs

if __name__=="__main__":
    main()
