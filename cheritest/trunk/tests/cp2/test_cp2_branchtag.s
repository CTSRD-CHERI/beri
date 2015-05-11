#-
# Copyright (c) 2012 Michael Roe
# Copyright (c) 2013 David Chisnall
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

.set mips64
.set noreorder
.set nobopt
.set noat

#
# Basic test of the CBTS and CBTU instructions.  
#


.global test
test:
.ent test
	dli       $a0, 0
	dli       $a1, 0

	# c0 should have a valid cap, c1 an invalid one
	ccleartag $c1, $c0

	# Check that the branches are taken when they should be and that their
	# delay slots execute.
	CBTS      $c0, clear1
	daddi     $a0, $a0, 1
cont1:
	CBTU      $c1, clear2
	daddi     $a1, $a1, 1
cont2:
	# Check that the branches are not taken when they shouldn't be and that
	# their delay slots execute.
	CBTS      $c1, clear3
	daddi     $a0, $a0, 2
cont3:
	CBTU      $c0, clear4
	daddi     $a1, $a1, 2
cont4:

	# By this point, a0 and a1 should both be 0b111 (7).  Each of the delay
	# slots will set one of the low bits and each of the branch targets will
	# set one of the next bits, but only one of the targets should be reached.

	jr        $ra
	nop  # branch-delay slot
clear1:
	b         cont1
	daddi     $a0, $a0, 4 # in delay slot
clear2:
	b         cont2
	daddi     $a1, $a1, 4 # in delay slot
# Should not be reached:
clear3:
	b         cont3
	daddi     $a0, $a0, 8 # in delay slot
clear4:
	b         cont4
	daddi     $a1, $a1, 8 # in delay slot
.end	test
