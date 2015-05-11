#!/usr/bin/env python
# Copyright (c) 2011 Robert M. Norton
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

# Script to export a fuzz test as a regression test.

import tools.gxemul, tools.sim
import os

def export_test(test_name, options):
    uncached_gxemul_log    = open(os.path.join("gxemul_log", test_name + '_gxemul.log'), 'rt')
    uncached_gxemul_status = tools.gxemul.MipsStatus(uncached_gxemul_log)
    cached_gxemul_log      = open(os.path.join("gxemul_log", test_name + '_gxemul_cached.log'), 'rt')
    cached_gxemul_status   = tools.gxemul.MipsStatus(cached_gxemul_log)

    new_name=options.name if options.name else test_name
    attrs = ""
    if test_name.find('tlb') != -1:
        attrs=attrs + "@attr('tlb')"
    print """from beritest_tools import BaseBERITestCase
from nose.plugins.attrib import attr
import os
import tools.sim
expected_uncached=["""
    for reg in xrange(len(tools.gxemul.MIPS_REG_NUM2NAME)):
        print "    0x%x," % uncached_gxemul_status[reg]
    print """  ]
expected_cached=["""
    for reg in xrange(len(tools.gxemul.MIPS_REG_NUM2NAME)):
        print "    0x%x," % cached_gxemul_status[reg]
    print """  ]
class %(testname)s(BaseBERITestCase):
  %(attrs)s
  def test_registers_expected(self):
    cached=bool(int(os.getenv('CACHED',False)))
    expected=expected_cached if cached else expected_uncached
    for reg in xrange(len(tools.sim.MIPS_REG_NUM2NAME)):
      self.assertRegisterExpected(reg, expected[reg])
""" % {'attrs':attrs, 'testname':new_name}

if __name__=="__main__":
    from optparse import OptionParser
    parser = OptionParser(usage="Usage: %prog [options] test_name")
    parser.add_option("-d", "--test-dir",help="Directory to put the exported test.", default="tests/fuzz_regressions")
    parser.add_option("-n", "--name",help="New name for the test (optional but recommended).", default="")
    (options, args) = parser.parse_args()
    if len(args) != 1:
        raise Exception("Please give exactly one test name.")
    test_name=args[0]
    export_test(test_name, options)

