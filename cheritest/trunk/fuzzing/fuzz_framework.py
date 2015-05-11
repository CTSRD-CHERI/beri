#-
# Copyright (c) 2012 Robert M. Norton
# All rights reserved.
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

NUM_GREGS=32

class Variation(object):
    pass

class EnumVariation(Variation):
    def __init__(self, values):
        self.values=values

    def iterate_values(self):
        for v in self.values:
            yield v

class RegisterVariation(EnumVariation):
    def __init__(self):
        super(RegisterVariation, self).__init__(("$r%d"%n for n in range(NUM_GREGS)))

class RRROpcodeVariation(EnumVariation):
    opcodes = """
    ADD
    ADDU
    SUB
    SUBU
    SLT
    SLTU
    AND
    OR
    XOR
    NOR 
    """.split()
    def __init__(self):
        super(RRROpcodeVariation, self).__init__(RRROpcodeVariation.opcodes)

class CrossVariation(Variation):
    def iterate_values(self):
        variations=inspect.getmembers(self.__class__, lambda m: isinstance(m,Variation))
        for p in itertools.product(*(v[1].iterate_values() for v in variations)):
            yield dict((variations[i][0],p[i]) for i in xrange(len(variations)))

class MIPSInstruction(CrossVariation):
    pass

class RRRInstructions(MIPSInstruction):
    opcode=RRROpcodeVariation()
    rd=RegisterVariation()
    rs=RegisterVariation()
    rt=RegisterVariation()

    def iterate_asm(self):
        for v in self.iterate_values():
            yield "%(opcode)s %(rd)s, %(rs)s, %(rt)s"%v    

class TestGenerator(object):
    pass

class InstructionPairGenerator(TestGenerator):
    
    def generate_test(self, n):
        pass
