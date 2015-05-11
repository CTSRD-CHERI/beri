#!/usr/bin/env python
#
# Copyright (c) 2013 Colin Rothwell
# All rights reserved.
#
# This software was developed by Colin Rothwell as part of his final year
# undergraduate project.
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
import re

def extract_results(result_string):
    pattern = r"(?P<count>\d+): (?P<tag>\w+) Result (?P<value>[0-9a-f]{8})\n"
    return re.findall(pattern, result_string)

def extract_results_from_file(filename):
    with open(filename) as fil:
        return extract_results(fil.read())

def main():
    if len(sys.argv) != 3:
        print 'Usage: compare_transcripts.py <transcript file> <transcript file>'
        return 1

    first_results = extract_results_from_file(sys.argv[1])
    second_results = extract_results_from_file(sys.argv[2])

    if first_results == second_results:
        print "Match!"
    else:
        print "Mismatch :("
        for i in range(len(first_results)):
            first = first_results[i]
            second = second_results[i]
            diff = abs(int(first[2], 16) - int(second[2], 16))
            if first != second:
                print first, second, 'Difference:', diff


if __name__ == '__main__':
    main()
