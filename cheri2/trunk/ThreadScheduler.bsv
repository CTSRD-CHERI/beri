/*-
 * Copyright (c) 2012-2013 Robert M. Norton
 * Copyright (c) 2012 SRI International
 * All rights reserved.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
 * license agreements.  See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.  BERI licenses this
 * file to you under the BERI Hardware-Software License, Version 1.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at:
 *
 *   http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 *
 ******************************************************************************
 *
 * Authors: 
 *   Robert Norton <rmn30@cam.ac.uk>
 * 
 ******************************************************************************
 *
 * Description: Thread Scheduler
 * 
 ******************************************************************************/

import MIPS::*;
import CHERITypes::*;

import ConfigReg::*;
import Debug::*;

interface ThreadScheduler;
  method ActionValue#(ThreadID) getDecision(); 
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkThreadScheduler(ThreadScheduler);
  Reg#(ThreadID) nextThread <- mkReg(0);
  method ActionValue#(ThreadID) getDecision(); 
    nextThread <= (nextThread + 1); // Wraps automatically
    return nextThread;
  endmethod
endmodule
