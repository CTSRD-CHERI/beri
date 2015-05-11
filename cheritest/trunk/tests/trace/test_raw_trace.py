#-
# Copyright (c) 2013 Colin Rothwell
# All rights reserved.
#
# This software was developed by and Colin Rothwell as part of his summer
# internship.
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
from beritest_tools import BaseBERITestCase


def read_trace_records(trace_file_name, record_count, record_width=32):
    with open(trace_file_name, 'rb') as trace_file:
        return trace_file.read(record_count * record_width)

class test_raw_trace(BaseBERITestCase):
    def test_uncached(self):
        '''Test trace from uncached memory is as expected'''
        actual = read_trace_records('log/test_raw_trace.trace', 5)
        expected = read_trace_records('tests/trace/uncached_expected.trace', 5)
        self.assertEqual(actual, expected, 'Uncached trace mismatch. Use the '
                         'readtrace program to debug.')

    def test_cached(self):
        '''Test trace from cached memory is as expected'''
        actual = read_trace_records('log/test_raw_trace_cached.trace', 7)
        expected = read_trace_records('tests/trace/cached_expected.trace', 7)
        self.assertEqual(actual, expected, 'Cached trace mismatch. Use the '
                         'readtrace program to debug.')
