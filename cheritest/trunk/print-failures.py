#-
# Copyright (c) 2011 Steven J. Murdoch
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
import xml.dom.minidom as minidom
import xml.etree.ElementTree as ET
import argparse

###
### Process the XML output of nose to show failing/error test cases
###

if sys.version < '2.7':
   print 'Python 2.7 or later needed for ".." notation in ElementTree findall()'
   sys.exit()

def prettyPrint(element):
  txt = ET.tostring(element)
  return minidom.parseString(txt).toprettyxml()

def prettyPrintItems(etree, tag, prefix, verbose):
  failure_count=0
  ## Find the parent tag of all matching tags 
  for e in etree.findall('.//%s/..'%tag):
    failure_count+=1
    if verbose:
      print prefix + prettyPrint(e)
    else:
      print prefix + e.attrib["name"]
  return failure_count 

def main():
  parser = argparse.ArgumentParser(description='Process the XML output of nose to show failing/error test cases.')
  parser.add_argument('fh', type=file, help='XML file (in xUnit format) to parse', metavar='FILE', nargs='+')
  parser.add_argument('--verbose', '-v', dest='verbose', action='store_true', help='Show full error/failure details')
  args = parser.parse_args() 
 
  failure_count = 0
  for fh in args.fh:
    etree = ET.parse(fh)
    failure_count += prettyPrintItems(etree, 'failure', fh.name+' F: ', args.verbose)
    failure_count += prettyPrintItems(etree, 'error', fh.name+' E: ', args.verbose)

  print "Failures: %d"%failure_count
  if failure_count:
    sys.exit(1)
  
if __name__=="__main__":
  main()
