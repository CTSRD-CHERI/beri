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

#!/bin/sh

# Skip the tests that are not expected to terminate with QEMU

mkdir -p qemu_log

# The extension for unaligned loads/stores is not supported

make obj/test_ld_unalign_ok.mem
cp /dev/null qemu_log/test_ld_unalign_ok.log

# Software interrupts are asynchronous

make obj/test_memory_flush.mem
cp /dev/null qemu_log/test_memory_flush.log

# CP0

# Count register advances at an unexpected rate

make obj/test_cp0_compare.mem
cp /dev/null qemu_log/test_cp0_compare.log
make obj/test_cp0_wait.mem
cp /dev/null qemu_log/test_cp0_wait.log

# BEV1 handler is in ROM

make obj/test_code_rom_relocation.mem
cp /dev/null qemu_log/test_code_rom_relocation.log
make obj/test_exception_bev0_trap.mem
cp /dev/null qemu_log/test_exception_bev0_trap.log
make obj/test_exception_bev1_trap.mem
cp /dev/null qemu_log/test_exception_bev1_trap.log

# CP2 (Capabilities)

# Fast CCall not supported

make obj/test_cp2_ccall_fast.mem
cp /dev/null qemu_log/test_cp2_ccall_fast.log
