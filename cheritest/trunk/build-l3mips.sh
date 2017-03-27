#!/bin/sh

#
# Copyright (c) 2015 Matthew Naylor
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

command -v mlton >/dev/null 2>&1 || \
  { echo >&2 "Please type 'sudo apt-get install mlton', then retry."; exit 1; }

if [ -d l3mips ]; then
  echo "Directory l3mips already present"
  echo "Remove l3mips directory if you wish to reinstall"
  exit
fi

git clone https://github.com/acjf3/l3mips
cd l3mips
wget http://downloads.sourceforge.net/project/polyml/polyml/5.5.2/polyml.5.5.2.tar.gz
tar -xf polyml.5.5.2.tar.gz
cd polyml.5.5.2/
./configure
make
export PATH=`pwd`:$PATH
export LIBRARY_PATH=`pwd`/libpolyml/.libs/:$LIBRARY_PATH
export LIBRARY_PATH=`pwd`/libpolymain/.libs/:$LIBRARY_PATH
cd ..
wget http://www.cl.cam.ac.uk/~acjf3/l3/l3.tar.bz2
mkdir L3
tar xf l3.tar.bz2 -C L3 --strip-components 1
cd L3
cat Makefile | sed 's/-Wl,-no_pie//g' > NewMakefile
mv NewMakefile Makefile
make
cd ..
cp L3/bin/* .
make CAP=256
make clean
make CAP=c128
make clean
echo
echo "==========================================================="
echo "Done"
echo "For fuzz testing against 256-bit capabilities, please type:"
echo "  export L3CHERI=l3mips/l3mips-cheri256"
echo ""
echo "For fuzz testing against 128-bit capabilities, please type:"
echo "  export L3CHERI=l3mips/l3mips-cheric128"
echo "==========================================================="
