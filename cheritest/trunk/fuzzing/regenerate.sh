#-
# Copyright (c) 2012 Robert M. Norton
# All rights reserved.
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

# Test to regenerate expected register values for fuzz regression tests.
# This is useful when the test framework changes causes addresses stored in registers to change value.

for TEST_S in tests/fuzz_regressions/*.s; do
    TEST_NAME=$(basename ${TEST_S/.s/})
    make gxemul_log/${TEST_NAME}_gxemul.log gxemul_log/${TEST_NAME}_gxemul_cached.log
    PYTHONPATH=. ./fuzzing/export_regression.py --name ${TEST_NAME} ${TEST_NAME} > tests/fuzz_regressions/${TEST_NAME}.py
done
