#-
# Copyright (c) 2013 Colin Rothwell
# All rights reserved.
#
# This software was developed by Colin Rothwell as part of his final year
# undergraduate project.
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

        .text
		.global exceptionhandler
		.ent exceptionhandler
exceptionhandler:
        dmfc0 $a0, $14 # Load exception address
        mfc0 $a1, $13 # Load cause register
        dmfc0 $a2, $8 # Load bad virtual address
        # Go the the C code handler
        dla $t0, handle_exception
        jalr $t0
        nop
        # Use return addess from handler
        dmtc0 $v0, $14
        eret
        .end exceptionhandler
