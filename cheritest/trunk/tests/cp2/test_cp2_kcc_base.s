#-
# Copyright (c) 2016 Michael Roe
# All rights reserved.
#
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
# project, funded by EPSRC grant EP/K008528/1.
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
# Test that the exception handler can run with a restricted PCC.
#

		.global test
test:		.ent test
		daddu 	$sp, $sp, -32
		sd	$ra, 24($sp)
		sd	$fp, 16($sp)
		daddu	$fp, $sp, 32

		#
		# Make $c27 a capability for the exception handler
		#

		cgetdefault $c1
		dla	$t0, bev0_handler
		csetoffset $c1, $c1, $t0
		cmove	$c27, $c1

		#
		# Set up exception handler
		#

		dli	$a0, 0xffffffff80000180
		dla	$a1, bev0_common_handler_stub
		dli	$a2, 12	# instruction count
		dsll	$a2, 2	# convert to byte count
		jal	memcpy
		nop		# branch delay slot	

		#
		# Make $KCC a restricted capability for bev0_common_handler_stub
		#

		cgetdefault $c1
		dli	$t0, 0xffffffff80000180
		csetoffset $c1, $c1, $t0
		dli	$t0, 256
		csetbounds $c1, $c1, $t0
		cmove	$c29, $c1

		dli	$a0, 0

		teq $0, $0 # Should raise an exception

		ld	$fp, 16($sp)
		ld	$ra, 24($sp)
		daddu	$sp, $sp, 32
		jr	$ra
		nop			# branch-delay slot
		.end	test

		.ent bev0_common_handler_stub
bev0_common_handler_stub:
		cjr	$c27
		nop
		.end bev0_common_handler_stub

bev0_handler:
		dli	$a0, 1
		dmfc0	$k0, $14	# EPC
		daddiu	$k0, $k0, 4	# EPC += 4 to bump PC forward on ERET
		dmtc0	$k0, $14
		nop
		nop
		nop
		nop
		eret
		.end bev0_handler


