#-
# Copyright (c) 2011 Jonathan Woodruff
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

#
# This test exercises movz and movn in true and false cases for each.  They
# take operands fed from preceding loads and feed into stores.  This case
# failed in compiled code due to movz and movn being a special case for
# pipeline forwarding.
#

		.global test
test:		.ent test

		#
		# This case was found in freeBSD and failed
		#
movz_strange: 

		sd	$zero, 128($sp)
		# Writeback invalidate so we'll (probably) take a cache miss later
		cache	0x15, 128($sp)

		li	$s8, 5
		li	$a1, 5
		li	$a0, 4
		li	$a2, 0
		sw      $a0, 68($sp)
		lw	$a0, 68($sp)
		subu	$a1, $s8, $a1
		move	$v0, $a0
		ld	$a2, 128($sp) # cache miss
		slt 	$v1, $a2, $a0
		movz	$v0, $a2, $v1
		subu	$s5, $a1, $v0
movz_false:
		li	$a0, 1
		li	$a1, -1
		sw      $a1, 0($sp)
		lw      $v0, 0($sp)
		lw      $v1, 0($sp)
		movz    $v1, $a0,$v0
		sw      $v1, 0($sp)
		lw      $s0, 0($sp)
movz_true:
		sw	$a1, 0($sp)
		lw	$v0, 0($sp)
		lw	$v1, 0($sp)
		movz	$v1, $a0, $zero
		sw	$v1, 0($sp)
		lw	$s1, 0($sp)
movn_false:
		sw	$a1, 0($sp)
		lw	$v0, 0($sp)
		lw	$v1, 0($sp)
		movn	$v1, $a0, $zero
		sw	$v1, 0($sp)
		lw	$s2, 0($sp)
movn_true:
		sw	$a1, 0($sp)
		lw	$v0, 0($sp)
		lw	$v1, 0($sp)
		movn	$v1, $a0, $v1
		sw	$v1, 0($sp)
		lw	$s3, 0($sp)

		jr	$ra
		nop			# branch-delay slot
		.end	test
