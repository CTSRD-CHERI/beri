#!/bin/sh
#-
# Copyright (c) 2014 SRI International
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

BUILD_TIME=`TZ=UTC date +%s`
BUILD_HOST=`hostname`
BUILD_PATH=`pwd`

GIT_VERSION=`git rev-parse HEAD 2> /dev/null`
if [ $? -eq 0 ]; then
    BUILD_SRC_REV=$GIT_VERSION
    BUILD_SRC_PATH=`git rev-parse --show-prefix`
else 
    BUILD_SRC_REV=`svnversion`
    BUILD_SRC_PATH=`svn info | grep ^URL | cut -d' ' -f2`
fi

sed -e "s|%%BUILD_TIME%%|${BUILD_TIME}|" \
    -e "s|%%BUILD_HOST%%|${BUILD_HOST}|" \
    -e "s|%%BUILD_PATH%%|${BUILD_PATH}|" \
    -e "s|%%BUILD_SRC_REV%%|${BUILD_SRC_REV}|" \
    -e "s|%%BUILD_SRC_PATH%%|${BUILD_SRC_PATH}|" \
    < "$1" > "$2"

