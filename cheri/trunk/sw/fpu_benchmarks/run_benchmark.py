#!/usr/bin/env python
#-
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
import array
import subprocess

def extract_name_and_data(line):
    image_name = line.split(' ', 1)[0][len('START'):]
    start = 'START' + image_name + ' '
    return image_name, line.strip()[len(start):-len('END')]

def get_data(text_data):
    result = []
    for i in range(0, len(text_data), 2):
        byte_hex = text_data[i:i+1]
        result.append(int(byte_hex, 16))
    return result

def main():
    for line in [l.rstrip() for l in sys.stdin.readlines()]:
        if line.startswith('START'):
            image_name, image_data = extract_name_and_data(line)
            with open(image_name.lower() + '_data', 'wb') as mandelbrot_file:
                mandelbrot_file.write(image_data)
        else:
            print line
            
if __name__ == '__main__':
    main()
