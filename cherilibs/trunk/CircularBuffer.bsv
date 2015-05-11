/*-
 * Copyright (c) 2012 Robert M. Norton
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
 * Author: Robert Norton <rmn30@cam.ac.uk>
 * 
 ******************************************************************************
 * 
 * Description:
 * 
 * Provides a circular buffer stored in BRAM. In order to simplify arithmetic
 * the size of the buffer is a power two of MINUS ONE. Enqueue may be called at
 * any time. If an enqueue occurs when the buffer is full then an item is dropped
 * from the head. Data enqueued when the buffer is empty will be available 
 * after two cycles, but at all other times the head is available immediately 
 * whenever the buffer is non-empty.
 * 
 ******************************************************************************/

import BRAMCore::*;
import StmtFSM::*;
import ConfigReg::*;

interface CircularBuffer#(numeric type log2size, type element_type);
  method Action       enq(element_type e);
  method Action       deq();
  method element_type first();
  method Bool         notEmpty();
  method Bool         notFull();
  method Bool         almostFull();
endinterface

module mkBRAMCircularBuffer(CircularBuffer#(log2size, element_type))
  provisos (Bits#(element_type, width_any), 
            Add#(TExp#(log2size), 0, size), 
            Min#(log2size, 1, 1));

  ConfigReg#(Bit#(log2size))       headPtr <- mkConfigReg(0); // Next address to read.
  ConfigReg#(Bit#(log2size))       tailPtr <- mkConfigReg(0); // Next address to write.
  BRAM_DUAL_PORT#(Bit#(log2size), element_type) bram <- mkBRAMCore2(valueOf(size), False);
  PulseWire                          doEnq <- mkPulseWire();
  PulseWire                          doDeq <- mkPulseWire();
  Reg#(Bool)                     readDelay <- mkReg(False);
  
  let full  = ((tailPtr + 1) == headPtr);
  let empty = (tailPtr == headPtr);
  
  let isAlmostFull = (headPtr - tailPtr) < 32 && !empty;
  
  let isNotEmpty = !empty && !readDelay;
  let isNotFull  = !full;
  
  //rule debug; 
  //  $display("%d: tailPtr: %d, nextHead: %d delay: %d %s", $time, tailPtr, headPtr, readDelay, full ? "FULL" : (empty ? "EMPTY" : ""));
  //endrule
  
  (* fire_when_enabled, no_implicit_conditions *)
  rule incHead;
    let nextHead = (doDeq || (doEnq && full)) ? (headPtr + 1) : headPtr;
    bram.b.put(False, nextHead, ?);
    headPtr   <= nextHead;
    tailPtr   <= doEnq ? (tailPtr + 1) : tailPtr;
    // If we are empty then data will not be available until cycle
    // after next because it has to pass through the BRAM (the read
    // request we put this cycle will get the old data).
    readDelay <= empty;
  endrule
  
  method Action enq(element_type e);
    bram.a.put(True, tailPtr, e);
    doEnq.send();
  endmethod
                                                           
  method Action deq() if (isNotEmpty);
    doDeq.send();
  endmethod
  
  method element_type first() if (isNotEmpty);
    return bram.b.read();
  endmethod
  
  method notEmpty();
    return isNotEmpty;
  endmethod
  
  method notFull();
    return isNotFull;
  endmethod
  
  method almostFull();
    return isAlmostFull;
  endmethod
endmodule

module mkTestBRAMCircularBuffer(Empty);
  CircularBuffer#(3, int) testBuf <- mkBRAMCircularBuffer();
  Reg#(int)                     i <- mkReg(0);
  
  function popFifo(f, expected);
    action
      let v = f.first();
      f.deq();
      $display("%d: Popped: %x %s", $time, v, (v==expected) ? "PASS":"FAIL");
    endaction
  endfunction
  

  
  Stmt test =  
  seq
    // Check that enq followed by immediate deq is safe (need extra cycle delay)
    testBuf.enq(42);
    popFifo(testBuf, 42);
    // Fill the queue then empty it again
    i<=0;
    while(i<7) seq
      action
        testBuf.enq(i);
        i<=i+1;
      endaction
    endseq
    
    i<=0;
    while(i<7) seq
      action
        popFifo(testBuf, i);        
        i<=i+1;
      endaction
    endseq
    
    // Overfill the queue
    i<=0;
    while(i<10) seq
      action
        testBuf.enq(i+16);
        i<=i+1;
      endaction
    endseq

    i<=3;
    while(i<10) seq  // attempt enq and deq simultaneously when full
      par
        popFifo(testBuf, i+16);
        testBuf.enq(i+32);
        i<=i+1;
      endpar
    endseq
    
    i<=3;
    while(i<10) seq  // Empty FIFO to finish
      action
        popFifo(testBuf, i+32);        
        i<=i+1;
      endaction
    endseq
  endseq;
  
  mkAutoFSM(test);
endmodule
