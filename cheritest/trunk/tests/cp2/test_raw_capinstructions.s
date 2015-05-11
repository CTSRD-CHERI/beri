#-
# Copyright (c) 2011 Steven J. Murdoch
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

		.global start
		.ent start
start:
                # get fields of a capability
		cgetperm  $a1,  $c2
		cgettype  $a1,  $c2
		cgetbase  $a1,  $c2
		cgetlen   $a1,  $c2
                cgettag   $a1,  $c2
                cgetunsealed $a1, $c2
		cgetpcc   $a1($c2)
		cgetcause $a1

                # set the fields of a capability
		dli       $a3,  0
		candperm  $c1,  $c2, $a3
		csettype  $c1,  $c2, $a3
		cincbase  $c1,  $c2, $a3
		csetlen   $c1,  $c2, $a3
                ccleartag $c1,  $c2
		csetcause $a3

		cmove     $c1,  $c2

		# store/load capability, register and immediate offset
		csc	  $c1,  $a3, 0($c2)
		clc       $c1,  $a3, 0($c2)

		# negative immmediate offset
		csc       $c1,  $a3, -1($c2)
		clc       $c1,  $a3, -1($c2)

                # store/load capability, register offset
                dla       $a3,  cap1
		cscr      $c1,  $a3($c2)
		clcr      $c1,  $a3($c2)

		# store/load capability, immediate offset
		csci      $c1,  0($c2)
		clci	  $c1,  0($c2)

		# load via capability, sign extend, register and immediate
                clb       $a1,  $a3, 0($c2)
                clh       $a1,  $a3, 0($c2)
                clw       $a1,  $a3, 0($c2)
                cld       $a1,  $a3, 0($c2)

		# negative immediate offset
		clb       $a1,  $a3, -1($c2)
		clh       $a1,  $a3, -1($c2)
		clw       $a1,  $a3, -1($c2)
		cld       $a1,  $a3, -1($c2)

                # load via capability, sign extend, register offset
                clbr      $a1,  $a3($c2)
                clhr      $a1,  $a3($c2)
                clwr      $a1,  $a3($c2)
                cldr      $a1,  $a3($c2)

		# load via capability, sign extend, immediate offset
		clbi      $a1,  0($c2)
		clhi      $a1,  0($c2)
		clwi      $a1,  0($c2)
		cldi      $a1,  0($c2)

		# load via capability, zero extend, register and immediate
                clbu      $a1,  $a3, 0($c2)
                clhu      $a1,  $a3, 0($c2)
                clwu      $a1,  $a3, 0($c2)

		# load via capability, zero extend, register offset
		clbur     $a1,  $a3($c2)
		clhur     $a1,  $a3($c2)
		clwur     $a1,  $a3($c2)

		# load via capability, zero extend, immediate offset
		clbui     $a1,  0($c2)
		clhui     $a1,  0($c2)
		clwui     $a1,  0($c2)

                # store via capability, register and immediate offset
                csb       $a1,  $a3, 0($c2)
                csh       $a1,  $a3, 0($c2)
                csw       $a1,  $a3, 0($c2)
                csd       $a1,  $a3, 0($c2)

		# negative immediate offset
		csb       $a1, $a3, -1($c2)
		csh       $a1, $a3, -1($c2)
		csw       $a1, $a3, -1($c2)
		csd       $a1, $a3, -1($c2)

                # store via capability, register offset
                csbr      $a1,  $a3($c2)
                cshr      $a1,  $a3($c2)
                cswr      $a1,  $a3($c2)
                csdr      $a1,  $a3($c2)

                # store via capability, immediate offset
                csbi      $a1,  0($c2)
                cshi      $a1,  0($c2)
                cswi      $a1,  0($c2)
                csdi      $a1,  0($c2)

		# store high byte/word/half-word via capability
                csbh      $a1,  $a3, 0($c2)
                cshh      $a1,  $a3, 0($c2)
                cswh      $a1,  $a3, 0($c2)

		# store high via capability, register offset
                csbhr     $a1,  $a3($c2)
                cshhr     $a1,  $a3($c2)
                cswhr     $a1,  $a3($c2)

		# store high via capability, immediate offset
                csbhi     $a1,  0($c2)
                cshhi     $a1,  0($c2)
                cswhi     $a1,  0($c2)

		# object capabilities
		csealcode $c1,  $c2
		csealdata $c1,  $c2, $c3
		cunseal   $c1,  $c2, $c3

		# load linked/store conditional
		clld      $t1, $a3, 0($c2)
		cscd      $t1, $a3, 0($c2)
		clldr     $t1, $a3($c2)
		cscdr     $t1, $a3($c2)
		clldi     $t1, 0($c2)
		cscdi     $t1, 0($c2)

		# check capability fields
		cmove $c1, $c0
		cmove $c2, $c0
		dli $a2, 0
		ccheckperm $c1, $a2
		cchecktype $c1, $c2
		
		
                # jumps
		dla       $t1, l0
		cjr       $t1($c0)
		# branch delay slot
		nop

l0:
		dla       $t1, l1
		cjalr     $t1($c0)
		# branch delay slot
		nop

l1:
		cmove    $c1, $c0
                cbts     $c1, l2
                # branch delay slot
		nop
l2:
                ccleartag $c1, $c1
		cbtu     $c1, l3
		# branch delay slot
		nop

l3:
                # crossing protection domains
		ccall    $c1,  $c2
		creturn

		cfromptr $c3, $c1, $zero
		ctoptr	 $t0, $c1, $c2

		# Dump registers in the simulator
		mtc0 $v0, $26
		nop
		nop

		# Terminate the simulator
		mtc0 $v0, $23
end:
		b end
		nop
		.end start

		.data
		.align	5                  # Must 256-bit align capabilities
cap1:		.dword	0x0123456789abcdef # uperms/reserved
		.dword	0x0123456789abcdef # otype/eaddr
		.dword	0x0123456789abcdef # base
		.dword	0x0123456789abcdef # length

