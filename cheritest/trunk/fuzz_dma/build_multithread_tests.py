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

from os import path
import subprocess
from string import Template
import sys

SCRIPT_DIR = path.dirname(path.realpath(__file__))
CHERITEST_DIR = path.dirname(SCRIPT_DIR)

TEST_NAME = 'tests/fuzz_dma/test_clang_dma_gen_{0}_threads_{1}.c'
TEST_PATH = path.join(CHERITEST_DIR, TEST_NAME)

TEMPLATE_FILENAME = path.join(SCRIPT_DIR, 'multithread_test_template.c')

GENERATE_NAME = 'x86-obj/generate_multithread_dma_test'
GENERATE_PROGRAM = path.join(CHERITEST_DIR, GENERATE_NAME)

def main():
    with open(TEMPLATE_FILENAME) as template_file:
        template = Template(template_file.read())

    try:
        tests = subprocess.check_output([GENERATE_PROGRAM] + sys.argv[1:])
    except subprocess.CalledProcessError as ex:
        print 'CALLED PROCESS ERROR', ex.output
        sys.exit(2)

    thread_count_min = int(sys.argv[1])
    thread_count_max = int(sys.argv[2])
    seed_min = int(sys.argv[3])
    seed_max = int(sys.argv[4])

    thread_count = thread_count_min
    seed = seed_min

    for test_data in tests.rstrip().split('\n'):
        assert seed_min <= seed <= seed_max
        assert thread_count_min <= thread_count <= thread_count_max

        fields = test_data.split('$')
        try:
            programs = fields[0]
            set_sources = fields[1]
            asserts = fields[2]
            source_addrs = fields[3]
            dest_addrs = fields[4]
        except IndexError as ex:
            print 'TC {0}, SEED {1}. {2}'.format(thread_count, seed, str(ex))
            print test_data
            sys.exit(1)

        with open(TEST_PATH.format(thread_count, seed), 'w') as out:
            out.write(template.substitute(
                thread_count=thread_count, seed=seed,
                source_addrs=source_addrs, dest_addrs=dest_addrs,
                programs=programs, set_sources=set_sources, asserts=asserts))

        seed += 1
        if seed > seed_max:
            thread_count += 1
            seed = seed_min

    sys.exit(0)

if __name__ == '__main__':
    main()
