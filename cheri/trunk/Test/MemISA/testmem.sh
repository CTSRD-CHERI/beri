# Copyright 2016 Matthew Naylor
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
# This software was developed by the University of Cambridge Computer
# Laboratory as part of the Rigorous Engineering of Mainstream
# Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
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

#!/bin/bash

# Parameters
# ==========

# Arguments are taken from environment variables where available.
# Elsewhere, defaults values are chosen.

START_SEED=${START_SEED-0}
NUM_TESTS=${NUM_TESTS-1000}
AXE=${AXE-axe}
MODEL=${MODEL-WMO}
NUM_THREADS=${NUM_THREADS-2}
DEPTH=${DEPTH-100}

###############################################################################

# Inferred parameters
# ===================

END_SEED=`expr \( $START_SEED + $NUM_TESTS \) - 1`
PATH=$PATH:.

# Sanity check
# ============

if [ ! `command -v ../../sim` ]; then
  echo Can\'t find simulator \'../../sim\'
  exit -1
fi

if [ ! `command -v $AXE` ]; then
  echo Please add \'axe\' to your PATH
  exit -1
fi

if [ "$MODEL" != SC  -a \
     "$MODEL" != TSO -a \
     "$MODEL" != PSO -a \
     "$MODEL" != WMO -a \
     "$MODEL" != POW ]; then
  echo Unknown consistency model \'$MODEL\'
  exit -1
fi

# Test loop
# =========

echo Testing against $MODEL model:

for (( I = $START_SEED; I <= $END_SEED; I++ )); do
  echo -ne "$I\r"

  # Generate trace
  DEPTH=$DEPTH NUM_THREADS=$NUM_THREADS SEED=$I ./gen.py

  # Build executable
  ./make.sh 2> /dev/null

  # Create mem64.hex
  cp main.bin ../../mem.bin
  pushd . > /dev/null
  cd ../../
  ../../cherilibs/trunk/tools/memConv.py
  popd > /dev/null
  
  # Run simulation
  ./runsim.py

  # Check with axe

  OUTCOME=`$AXE check $MODEL trace.axe 2>> errors.txt`
  if [ "$OUTCOME" == "OK" ]; then
    :
  else
    if [ "$OUTCOME" == "NO" ]; then
      echo -e "\n\nFailed $MODEL with seed $I"
      echo "See trace.axe for counterexample"
      exit -1
    else
      echo -e "\n\nError during trace generation with seed $I"
      echo "See errors.txt for details"
      exit -1
    fi
  fi
done

echo -e "\n\nOK, passed $NUM_TESTS tests"
