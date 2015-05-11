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

TEST_NAME=$1
if [ -z "$TEST_NAME" ]; then
    echo Please specify a test name.
    exit 1
fi
# Slightly change test name to avoid confusion.
NEW_NAME=${TEST_NAME/test_fuzz/test_regfuzz}

make gxemul_log/${TEST_NAME}_gxemul.log gxemul_log/${TEST_NAME}_gxemul_cached.log
cp tests/fuzz/${TEST_NAME}.s tests/fuzz_regressions/${NEW_NAME}.s || exit 1
PYTHONPATH=. ./fuzzing/export_regression.py --name ${NEW_NAME} ${TEST_NAME} > tests/fuzz_regressions/${NEW_NAME}.py
