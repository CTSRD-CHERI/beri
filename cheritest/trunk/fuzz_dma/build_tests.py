#
# Copyright (c) 2015 Colin Rothwell
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

import sys
import subprocess
from string import Template

TEST_NAME = '../tests/fuzz_dma/test_clang_dma_generated_{0}.c'

def main():
    with open('test_template.c') as template_file:
        template = Template(template_file.read())

    try:
        tests = subprocess.check_output(
            ['../x86-obj/generate_dma_test', sys.argv[1], sys.argv[2]])
    except subprocess.CalledProcessError as ex:
        print ex.output
        return 1

    test_no = int(sys.argv[1]);
    for line in tests.rstrip().split('\n'):
        try:
            program, setsource, sourcesize, asserts, destsize = line.split('$')
        except Exception as ex:
            print test_no, ex, line
            break

        if len(setsource) == 0:
            print ('Test with seed {0} does no transfers, not '
                   'generated...'.format(test_no))
        else:
            with open(TEST_NAME.format(test_no), 'w') as out:
                out.write(template.substitute(
                    program=program, setsource=setsource, sourcesize=sourcesize,
                    asserts=asserts.replace(';', ';\n'), destsize=destsize))
        test_no += 1

    return 0

if __name__ == '__main__':
    main()
