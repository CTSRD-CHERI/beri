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

import Vector::*;
import FIFOF::*;
import ConfigReg::*;
import Assert::*;

import MIPS::*;
import CHERITypes::*;
import Library::*;
import Debug::*;
import EHR::*;

interface ThreadScheduler;
  method ActionValue#(ThreadID) getDecision();
  method Action suspendThread(ThreadID thread);
  method Action resumeThread(ThreadID thread);
  method Bool   isThreadRunning(ThreadID thread);
endinterface

(* synthesize, options="-aggressive-conditions" *)
module mkThreadScheduler(ThreadScheduler);
  FIFOF#(ThreadID)                     runningQ <- mkSizedFIFOF(valueOf(NumThreads)+1);
  FIFOF#(ThreadID)                     waitingQ <- mkSizedFIFOF(valueOf(NumThreads)+1);
  Vector#(NumThreads, EHR#(3,Bool))  threadRunning <- replicateM(mkEHR(True));
  Reg#(UInt#(8))                      waitCount <- mkReg(minBound);
  Reg#(Bool)                        initialised <- mkReg(False);

  rule initialise if (!initialised);
    if (waitCount < unpack(fromInteger(valueOf(NumThreads))))
      begin
        runningQ.enq(pack(truncate(waitCount)));
        waitCount <= waitCount + 1;
      end
    else
      begin
        initialised <= True;
      end
  endrule

  // Called by fetch/CP0.getNextThread
  method ActionValue#(ThreadID) getDecision() if (initialised);
    waitCount <= waitCount + 1;

    Bool suspendingRunning = (runningQ.notEmpty && !threadRunning[runningQ.first][2]);
    Bool resumingWaiting   = (waitingQ.notEmpty &&  threadRunning[waitingQ.first][2]);
    ThreadID ret = ?;
    if (suspendingRunning)
      begin
        ThreadID thread <- popFIFOF(runningQ);
        waitingQ.enq(thread);
        ret = thread;
      end
    else if (resumingWaiting)
      begin
        ThreadID thread <- popFIFOF(waitingQ);
        runningQ.enq(thread);
        ret = thread;
      end
    else if ((waitCount == 0 || !runningQ.notEmpty) && waitingQ.notEmpty)
      begin
        // Periodically run an instruction from a waiting thread to
        // see if it has an interrupt waiting.  If there is an
        // interrupt the thread will be resumed, otherwise we will
        // take a fake Ex_Suspended exception to return us to
        // instruction following the WAIT.  Do the same if there are
        // no running threads, as we might as well keep busy (we're
        // not trying to save power).
        let waitingThread <- popFIFOF(waitingQ);
        waitingQ.enq(waitingThread);
        ret = waitingThread;
      end
    else if (runningQ.notEmpty)
      begin
        ThreadID runningThread <- popFIFOF(runningQ);
        runningQ.enq(runningThread);
        ret = runningThread;
      end
    else
      dynamicAssert(False, "Shouldn't have reached end of if statement!");
    return ret;
  endmethod

  // Called by CP0 resp
  method Action suspendThread(ThreadID thread);
    debug2("sched", $display("Suspend thread %d:", thread));
    threadRunning[thread][0] <= False;
  endmethod

  // Called by CP0 resp
  method Action resumeThread(ThreadID thread);
    debug2("sched", $display("Suspend thread %d:", thread));
    threadRunning[thread][0] <= True;
  endmethod

  // Called by CP0 checkException
  method Bool isThreadRunning(ThreadID thread);
    return threadRunning[thread][1];
  endmethod
endmodule
