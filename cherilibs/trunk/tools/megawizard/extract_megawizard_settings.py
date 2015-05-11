#!/usr/bin/env python

#-
# Copyright (c) 2014 Theo Markettos
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

# Convert the verilog output of Altera's Megawizard tool into a configuration
# file that can be fed back in to the command line version qmegawiz

import verilogParse
import os
import gc
import sys
from pyparsing import ParseException

def findParameters(tree):
    "Recurse through a parsed Verilog file looking for the 'defparam' section"
    #print type(tree), tree
    if type(tree) is list:
        for x in range(0,len(tree)):
            item = tree[x]
            if type(item) == str and item=='defparam':
                #print tree
                return tree[x+1:len(tree)-1]  # omit 'defparam' and trailing semicolon
            else:
                child = findParameters(item)
                if child != '':
                    return child
    return ''

# command line parameters
componentType = sys.argv[1]
inputFile = sys.argv[2]
outputFile = sys.argv[3]

# set up a parser to handle Verilog
VerilogBNF = verilogParse.Verilog_BNF()

# read and parse the megawizard verilog code
f = open(inputFile,'rb')
try:
	tokens = VerilogBNF.parseString(f.read())
	f.close()
except ParseException, err:
	print err.line
	print " "*(err.column-1) + "^"
	print err

# look for the defparams section that holds the configuration information
parameters=findParameters(tokens.asList())

# parse it and check it's sane
paramDict = {}
for param in parameters:
    assert(param[1]=='=')   # error if we aren't a list of assignments
    key = param[0]
    [component, id] = key.split('.')
#    assert(component == componentType+'_component') # check we're the right component
    paramDict[id]=param[2]

# now we're happy everything is represented as a dict, flatten it out to text again
paramText = "\n".join(["%s=%s" % (key,value) for [key, value] in paramDict.items()])

# output the result
out = open(outputFile,'wb')
out.write(paramText)
out.close()

