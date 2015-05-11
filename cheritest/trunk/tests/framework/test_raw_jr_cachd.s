#-
# Copyright (c) 2011 Robert N. M. Watson
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
# This is a regression test for a CHERI bug in which, following a jump into
# cached memory, several instructions that follow the jump are read in as
# nops.
#

		.global start
start:
		dli	$a0, 0x1111111111111111
		dla	$t0, cached_start
		dli	$t1, 0x00ffffffffffffff
		and	$t0, $t0, $t1
		dli	$t1, 0x9800000000000000
		or	$t0, $t0, $t1
		jr	$t0
		nop

cached_start:
		dli	$a0, 0x0123456789abcdef

		# Dump registers in the simulator
		mtc0	$v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0	$v0, $23

		#
		# In the case where the simulator doesn't terminate (perhaps			# because we're not in simulation), jump back to the uncached
		# address.  Some test frameworks use the 'end' symbol to set
		# a breakpoint and/or confirm that the test exited properly,
		# and we need to use the right one.
		#
		dla	$t2, end
		j	$t2
		nop
end:
		b end
		nop
