#-
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2013 Alexandre Joannou
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
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


from beritest_tools import BaseICacheBERITestCase
from nose.plugins.attrib import attr

#
# XXX: our test code saves the CP0 config register in self.MIPS.s1 so that
# we can determine how this test should behave. Our test cases don't
# currently check that, so may return undesired failures. The third check
# below should be conditioned on (DC > 0) || (SC == 1) -- i.e., a cache is
# present, which might cause it not to incorrectly fire for gxemul.
#

class test_cache_instruction_instruction(BaseICacheBERITestCase):

    @attr('cache')
    @attr('dumpicache')
    def test_completion(self):
        self.assertTagInvalid ( 10  , "icache line index 10  was not invalidated" )
        self.assertTagValid   ( 20  , "icache line index 20  was not fetched"     )
        self.assertTagInvalid ( 132 , "icache line index 132 was not invalidated" )
        self.assertTagValid   ( 227 , "icache line index 227 was not fetched"     )
        self.assertTagValid   ( 83  , "icache line index 83  was not fetched"     )
        self.assertTagValid   ( 500 , "icache line index 500 was not fetched"     )
        self.assertTagInvalid ( 404 , "icache line index 404 was not invalidated" )
