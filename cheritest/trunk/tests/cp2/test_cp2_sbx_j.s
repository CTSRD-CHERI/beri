#-
# Copyright (c) 2013 Jonathan Woodruff
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
# Test that j (jump) works in a sandbox
#

sandbox:
		dli     $a0, 1
		j	20
		nop
		cjr     $c24
		nop			# Branch delay slot
		cjr     $c24
		li	$a2, 1		# Branch delay slot

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# $a0 will be set to 1 if sandbox is called
		#

		dli     $a0, 0

		#
		# $a2 will be set to 1 if jump works
		#

		dli	$a2, 0

		#
		# Jump to the sandbox
		#

		dla     $t0, sandbox
		cincoffset	$c1, $c0, $t0
		dli			$t0, 28 # Size of sandbox
		csetbounds	$c1, $c1, $t0 
		cjalr   $c1, $c24
		nop			# Branch delay slot

finally:
		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# Branch delay slot
		.end	test


