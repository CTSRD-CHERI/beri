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
# Test that the CHERI counter device is present, returns sequential values,
# and doesn't accept values written to it.  Explicitly use uncached xkphys
# addresses.  All accesses in this test are 64-bit.
#

		.global start
start:
		dli	$t0, 0x900000007f800000

		#
		# Read three times, we'll make sure they are all different.
		#
		ld	$a0, 0($t0)
		ld	$a1, 0($t0)
		ld	$a2, 0($t0)

		#
		# Write once
		#
		sd	$zero, 0($t0)

		#
		# Read back
		#
		ld	$a3, 0($t0)

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop
		nop
		nop
		nop
		nop

		# Terminate the simulator
		mtc0 $v0, $23
end:
		b end
		nop
