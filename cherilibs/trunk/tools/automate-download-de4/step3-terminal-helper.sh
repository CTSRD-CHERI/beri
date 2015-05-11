#!/bin/bash
#-
# Copyright (c) 2012 Simon W. Moore
# Copyright (c) 2012 Jonathan Woodruff
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

source /usr/groups/ecad/setup.bash 2> /dev/null > /dev/null
CHERITOOLS=~/Repositories/ctsrd/cherilibs/trunk/tools/debug
echo "Clearing interrupt key so that ctrl-C will be sent to CHERI rather than stop"
echo "the nios2-terminal.  Kill the nios2-terminal by closing the window."
stty intr ''
stty quit ''
stty susp ''
echo "Tip - to make the terminal work (e.g. for vi), use:"
echo "  setenv TERM ansi"
echo "To mirror the MTL-LCD output on the nios2-terminal, use:"
echo "  watch -W ttyv0"
nios2-terminal --instance 1
