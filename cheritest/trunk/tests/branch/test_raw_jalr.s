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
# Test jump and link register.  Confirm that control flow is roughly as
# expected, that the desired register updated, and that $ra is *not* updated.
#

		.global start
start:   
    li	$a0, 0xdead				# Clear register
    li	$a3, 0xdead				# Clear register
    li	$a4, 0xdead				# Clear register
    li	$a5, 0xdead				# Clear register
		li	$a0, 1
		dla	$a1, desired_return_address	# To check $a2 against
		li	$ra, 0				# To get 0 after jalr
		dla	$t0, jal_target		# Load jump target
		jalr	$a2, $t0
		daddi	$a3, $a2, 0		# Branch-delay slot, testing forwarding
desired_return_address:
		li	$a4, 4				# Shouldn't run
jal_target:
		li	$a5, 5				# Should run

		# Dump registers in the simulator
		mtc0	$v0, $26
		nop
		nop

		# Terminate the simulator
	        mtc0	$v0, $23
end:
		b end
		nop
