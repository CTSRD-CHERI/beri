#-
# Copyright (c) 2010-2011 Steven J. Murdoch
# Copyright (c) 2011 Wojciech A. Koszek
# Copyright (c) 2012 Robert N. M. Watson
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2013 SRI International
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
# CHERI2

## Bluespec 

# pickup Cambridge Computer Laboratory configuration files where possible
# and ensure we're using Quartus 12.1

if [ -f /local/ecad/setup.bash ] ; then
    . /local/ecad/setup.bash
elif [ -f /usr/groups/ecad/setup.bash ] ; then
    . /usr/groups/ecad/setup.bash
fi

# Edit these enviornmental variables for the local setup!

PATH=/usr/groups/ctsrd/local/bin:/usr/groups/ecad/mips/sde-6.06/bin:$PATH
export PATH

# if [ ! -n "${QUARTUS_ROOTDIR}" ]; then
# 	export QUARTUS_ROOTDIR=/usr/groups/ecad/altera/current/quartus
# fi
# bsversion=current
# if [ ! -n "${ECAD_LICENSES}" ]; then
# 	export ECAD_LICENSES=/usr/groups/ecad/licenses
# fi
# BLUESPEC_LICENSE_FILE="$ECAD_LICENSES/bluespec.lic"
# if [ ! -n "${LM_LICENSE_FILE}" ]; then
# 	export LM_LICENSE_FILE="$LM_LICENSE_FILE:$BLUESPEC_LICENSE_FILE"
# fi
# if [ ! -n "${BLUESPEC}" ]; then
# 	export BLUESPEC=/usr/groups/ecad/bluespec/$bsversion
# fi
# if [ ! -n "${BLUESPECDIR}" ]; then
# 	export BLUESPECDIR=/usr/groups/ecad/bluespec/$bsversion/lib
# fi
# # avoid Qsys build collisions in /tmp on shared machines
# if [ ! -n "${TEMP}" ]; then
#         export TEMP=/tmp/$USER
# fi
# if [ ! -n "${TMP}" ]; then
#         export TMP=/tmp/$USER
# fi

# if [ -d "$QUARTUS_ROOTDIR/bin" ] ; then
#   PATH="$PATH:$QUARTUS_ROOTDIR/bin"
# fi
# if [ -d "$QUARTUS_ROOTDIR/sopc_builder/bin" ] ; then
#   PATH="$PATH:$QUARTUS_ROOTDIR/sopc_builder/bin"
# fi
# if [ -d "$BLUESPEC/bin" ] ; then
#   PATH="$PATH:$BLUESPEC/bin"
# fi
