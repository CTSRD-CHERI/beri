#! /usr/bin/env python
#-
# Copyright (c) 2016 Alexandre Joannou
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

import argparse
from datetime import datetime
from math import log

################################
# Parse command line arguments #
################################

parser = argparse.ArgumentParser(description='script parameterizing the cheri tags controller')

def auto_int (x):
    return int(x,0)

parser.add_argument('-v', '--verbose', action='store_true', default=False,
                    help="turn on output messages")
parser.add_argument('-c','--cap-size', type=auto_int, default=256,
                    help="capability size in bits")
parser.add_argument('-s','--structure', type=auto_int, nargs='+', default=[0],
                    help="list from leaf to root of branching factors describing the tags tree")
parser.add_argument('-t','--top-addr', type=auto_int, default=0x40000000,
                    help="memory address at which the tags table should start growing down from")
parser.add_argument('-a','--addr-align', type=auto_int, default=32,
                    help="alignement requirement (in bytes) for table levels addresses")
parser.add_argument('-m','--mem-size', type=auto_int, default=(2**30+2**20),
                    help="size of the memory to be covered by the tags")
parser.add_argument('-b','--bsv-inc-output', nargs='?', const="TagTableStructure.bsv", default=None,
                    help="generate Bluespec MultiLevelTagLookup module include configuration file")
parser.add_argument('-l','--linker-inc-output', nargs='?', const="tags-params.ld", default=None,
                    help="generate tags configuration linker include file")

args = parser.parse_args()

if args.verbose:
    def verboseprint(msg):
        print msg
else:   
    verboseprint = lambda *a: None

####################################
# values the script will work with #
####################################

verboseprint("Deriving tags configuration from parameters:")
verboseprint("mem_size = %d bytes" % args.mem_size)
verboseprint("cap_size = %d bits" % args.cap_size)
verboseprint("top_addr = 0x%x" % args.top_addr)
verboseprint("addr_align = %d bytes (%d addr bottom bits to ignore)" % (args.addr_align, log(args.addr_align,2)))
verboseprint("structure = %s" % args.structure)

######################
# compute parameters #
######################

class TableLvl():
    def __init__ (self, startAddr, size):
        self.startAddr = startAddr
        self.size = size
    def __repr__(self):
        return str(self)
    def __str__(self):
        return "{0x%x, %d bytes}" % (self.startAddr, self.size)

def table_lvl(lvl):
    mask = ~0 << int(log(args.addr_align,2))
    if lvl == 0:
        size = args.mem_size / args.cap_size
        addr = args.top_addr-size
    else:
        t = table_lvl(lvl-1)
        size = t.size / args.structure[lvl]
        addr = t.startAddr-size
    return TableLvl (addr&mask, size)

if args.cap_size > 0:
    lvls = map (table_lvl, range(0,len(args.structure)))
else:
    lvls = [TableLvl(args.top_addr,0)]

###############################
# display computed parameters #
###############################

verboseprint("-"*80)
verboseprint("lvls = %s" % lvls)
verboseprint("last_addr = 0x%x" % (lvls[len(lvls)-1].startAddr-1))
verboseprint("tags_size = %d bytes" % (args.top_addr-lvls[len(lvls)-1].startAddr))

######################################################
# generate bluespec table configuration include file #
######################################################

if args.bsv_inc_output:
    verboseprint("-"*80)
    verboseprint("generating Bluespec MultiLevelTagLookup module include configuration file %s" % args.bsv_inc_output)
    f = open(args.bsv_inc_output,'w')
    header = """/*-
 * Copyright (c) 2016 Alexandre Joannou
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
 * license agreements.  See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.  BERI licenses this
 * file to you under the BERI Hardware-Software License, Version 1.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at:
 *
 *   http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 */
"""
    header += "\n// This file was generated by the tagsparams.py script"
    header += "\n// %s\n\n" % str(datetime.now())
    decl = "Vector#(%d, Integer) tableStructure;\n" % len(args.structure)
    fill = map(
            lambda (n,g): "tableStructure[%d] = %d;\n" % (n,g),
            zip(range(0,len(args.structure)),args.structure))
    f.write(header)
    f.write(decl)
    map(f.write,fill)

#######################################################
# generate ld script table configuration include file #
#######################################################

if args.linker_inc_output:
    verboseprint("-"*80)
    verboseprint("generating tags configuration linker include file %s" % args.linker_inc_output)
    f = open(args.linker_inc_output,'w')
    header = """/*-
 * Copyright (c) 2016 Alexandre Joannou
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
 * license agreements.  See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.  BERI licenses this
 * file to you under the BERI Hardware-Software License, Version 1.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at:
 *
 *   http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 */
"""
    header += "\n/* This file was generated by the tagsparams.py script */"
    header += "\n/* %s */\n\n" % str(datetime.now())
    decl = "__tags_table_size__ = 0x%x;" % (args.top_addr-lvls[len(lvls)-1].startAddr)
    f.write(header)
    f.write(decl)
