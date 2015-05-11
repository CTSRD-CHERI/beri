#!/usr/bin/python
#-
# Copyright (c) 2012 Robert M. Norton
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

import Image, struct, sys

if __name__=="__main__":
    from optparse import OptionParser
    usage = "Usage: %prog [options] InputImage"
    parser = OptionParser(usage=usage)
    parser.add_option("-o", "--output",
                      help="File in which to output binary image (default %default).", default="img.bin")
    parser.add_option("-w", "--width",
                      help="Width of frame buffer in pixels (default %default).", type='int', default=800)
    parser.add_option("", "--height",
                      help="Height of frame buffer in pixels (default %default).", type='int', default=480)
    (options, args) = parser.parse_args()
    i=Image.open(args[0])
    (w,h) = i.size
    if w < options.width or h < options.height:
        sys.stderr.write("Supplied image is too small.")
    pixels = i.getdata().pixel_access()
    outFile = open(options.output, 'wb')
    for y in xrange(options.height):
        for x in xrange(options.width):
            (r,g,b) = pixels[(x,y)]
            outFile.write(struct.pack('BBBB',b,g,r,0))
    outFile.close()
