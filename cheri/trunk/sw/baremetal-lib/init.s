#-
# Copyright (c) 2010 Gregory A. Chadwick
# Copyright (c) 2010-2013 Jonathan Woodruff
# Copyright (c) 2011 Robert N. M. Watson
# Copyright (c) 2011 Simon W. Moore
# Copyright (c) 2011 Wojciech A. Koszek
# Copyright (c) 2013 A. Theodore Markettos
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
# CHERI init.s
#
# Bits within this file get started first.
#
# Content of this file will be present in FPGA's BRAM located at 0x4000_0000.
# This file assumes that memory available under 0x9000_0000_0000_0000 is
# uncached.
# 

.set mips64
.set noreorder
.set nobopt
.set noat

		#
		# On a multithreaded or multicore CPU, spin all cores/threads
		# apart from core/thread 0.
		#

		dmfc0 $k0, $15, 6
		andi $k0, $k0, 0xffff
spin_core:
		bnez $k0, spin_core
		nop

		dmfc0 $k0, $15, 7
		andi $k0, $k0, 0xffff
spin_thread:
		bnez $k0, spin_thread
		nop

		#
		# Enable all coprocessors
		#

		mfc0 $k0, $12		# CP0 Status
		li $k1, 0xF0000000
		or $k0, $k0, $k1
		mtc0 $k0, $12

		#
		# Setup stack to the address configured in the linker script.
		# ld(1) takes care of inserting additional instructions
		# before startMain gets going in order to make sp = __sp
		#

		dla $sp, __sp			

		#
		# Set up exception handler
		#

		jal	bev_clear
		nop
		dla	$a0, common_handler
		jal	bev0_handler_install
		nop
		dla	$a0, common_handler
		jal	set_bev1_common_handler
		nop
		dla	$a0, tlb_handler
		jal	set_bev0_tlb_handler
		nop
		jal	set_bev1_tlb_handler
		nop
		jal	set_bev0_xtlb_handler
		nop
		jal	set_bev1_xtlb_handler
		nop
startMain:
		daddu 	$sp, $sp, -32		# Allocate 32 bytes of stack space
		dla	$k0, runcached
		jr	$k0
		nop
runcached:
		dla $t9, main   # llvm requires the invoked address to be in $t9
		jal $t9
		nop
		mtc0 $at, $23

end:
		b end
		nop

