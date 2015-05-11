# This script is designed to be sourced, it should not have a bangpath
#-
# Copyright (c) 2010-2011 Steven J. Murdoch
# Copyright (c) 2011 Wojciech A. Koszek
# Copyright (c) 2012 Robert N. M. Watson
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2013 Simon W. Moore
# Copyright (c) 2013 Robert M. Norton
# Copyright (c) 2013 Colin Rothwell
# Copyright (c) 2013 Bjoern A. Zeeb
# Copyright (c) 2014 A. Theodore Markettos
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
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

## Bluespec

# pickup Cambridge Comptuer Laboratory configuration files where possible
# and ensure we're using Quartus 13.1
QUARTUS_VERSION=13v1

if [ -n "${QUARTUS_SETUP_SH}" -a -r "${QUARTUS_SETUP_SH}" ] ; then
    . ${QUARTUS_SETUP_SH}
elif [ -f ./setup-local.sh ] ; then
    . ./setup-local.sh
elif [ -f /local/ecad/setup-quartus${QUARTUS_VERSION}.bash ] ; then
    . /local/ecad/setup-quartus${QUARTUS_VERSION}.bash
    export PATH=/usr/groups/ctsrd/local/bin:/usr/groups/ecad/mips/sde-6.06/bin:$PATH
elif [ -f /usr/groups/ecad/setup-quartus${QUARTUS_VERSION}.bash ] ; then
    . /usr/groups/ecad/setup-quartus${QUARTUS_VERSION}.bash
    export PATH=/usr/groups/ctsrd/local/bin:/usr/groups/ecad/mips/sde-6.06/bin:$PATH
else
    echo "************************************************"
    echo "Failed to find a tools configuration script."
    echo "1. Have you created a cheri/trunk/setup-local.sh?"
    echo "   See setup-local-example.sh for an example"
    echo "2. You must be in cheri/trunk to source setup.sh"
    echo "************************************************"
fi
