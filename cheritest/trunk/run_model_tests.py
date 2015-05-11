#!/usr/bin/env python

#-
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

import re
import os
from os import path
import sys
import subprocess

def main():
    tests = sorted([fn for fn in os.listdir('x86-obj')
                    if re.match(r'^dmamodel_[^\.]+$', fn) is not None])
    test_files = [path.abspath(path.join('x86-obj', fn)) for fn in tests]
    test_names = [fn.split('_', 1)[1] for fn in tests]
    for name, fn in zip(test_names, test_files):
        sys.stdout.write('{0}. '.format(name))
        try:
            subprocess.check_output([fn])
        except subprocess.CalledProcessError as ex:
            print 'FAILED! (assert on line {0})'.format(ex.output.strip())
            continue
        print 'Passed.'

if __name__=='__main__':
    main()
