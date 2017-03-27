/*
 * Copyright 2015 Matthew Naylor
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream
 * Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
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
 */

import MIPS::*;
import ForwardingPipelinedRegFile::*;
import ForwardingPipelinedRegFileHighFrequency::*;
import StmtFSM   :: *;
import BlueCheck :: *;
import Clocks    :: *;
import FIFO::*;

typedef ForwardingPipelinedRegFileIfc#(MIPSReg, 4) RFIfc;

typedef struct {
  Bit#(3) readA;
  Bit#(3) readB;
  Bit#(3) dest;
  WriteType write;
} Request deriving (Bits, Eq, FShow);

typedef enum {
  True1,
  True2,
  True3,
  Flush
} CommitChance deriving (Bits, Eq, FShow);

// Reset version, for iterative deepening
module [BlueCheck] checkForwardingRegFileWithReset#(Reset r) ();
  /* Specification instance */
  RFIfc spec <- mkForwardingPipelinedRegFile(reset_by r);

  /* Implmentation instance */
  RFIfc imp <- mkForwardingPipelinedRegFileHighFrequency(reset_by r);
  
  Reg#(Epoch)  epoch   <- mkReg(reset_by r, 0);
  FIFO#(Epoch) epochsA <- mkSizedFIFO(reset_by r, 8);  
  FIFO#(Epoch) epochsB <- mkSizedFIFO(reset_by r, 8);

  function Action reqRegs(RFIfc rf, Request r) =
    action
      ReadReq newReq = ReadReq{
                        epoch: epoch,
                        rawReq: False,
                        fromDebug: False,
                        a: zeroExtend(r.readA),
                        b: zeroExtend(r.readB),
                        write: r.write,
                        dest: zeroExtend(r.dest)
      };
      rf.reqRegs(newReq);
    endaction;
    
  function Action reqRegsSE(RFIfc rf, Request r) =
    action
      ReadReq newReq = ReadReq{
                        epoch: epoch,
                        rawReq: False,
                        fromDebug: False,
                        a: zeroExtend(r.readA),
                        b: zeroExtend(r.readB),
                        write: r.write,
                        dest: zeroExtend(r.dest)
      };
      rf.reqRegs(newReq);
      epochsA.enq(epoch);
    endaction;
  
  function ActionValue#(ReadRegs#(MIPSReg)) readWrite(RFIfc rf, MIPSReg data, Bool write) =
    actionvalue
      ReadRegs#(MIPSReg) result <- rf.readRegs;
      rf.writeRegSpeculative(data, write);
      if (epochsA.first != epoch) result = unpack(0);
      return result;
    endactionvalue;
 
  function ActionValue#(ReadRegs#(MIPSReg)) readWriteSE(RFIfc rf, MIPSReg data, Bool write) =
    actionvalue
      ReadRegs#(MIPSReg) result <- rf.readRegs;
      rf.writeRegSpeculative(data, write);
      if (epochsA.first != epoch) result = unpack(0);
      epochsB.enq(epochsA.first);
      epochsA.deq;
      return result;
    endactionvalue;
    
  function Action writeReg(RFIfc rf, MIPSReg data, CommitChance commit) =
    action
      Bool committing = commit!=Flush;
      if (epochsB.first != epoch) committing = False;
      rf.writeReg(data, committing);
    endaction;
  
  function Action writeRegSE(RFIfc rf, MIPSReg data, CommitChance commit) =
    action
      Bool committing = commit!=Flush;
      if (!committing) epoch <= epoch + 1;
      if (epochsB.first != epoch) committing = False;
      epochsB.deq;
      rf.writeReg(data, committing);
    endaction;
  
  equiv("reqRegs",    reqRegs(spec), reqRegsSE(imp));
  equiv("readWrite",  readWrite(spec), readWriteSE(imp));
  equiv("writeReg",   writeReg(spec), writeRegSE(imp));
endmodule

// Iterative deepening version
module [Module] testForwardingRegFileID ();
  Clock clk <- exposeCurrentClock;
  MakeResetIfc r <- mkReset(0, True, clk);
  //blueCheckID(checkForwardingRegFileWithReset(r.new_rst), r);
  
  // BlueCheck parameters
  BlueCheck_Params params = bcParamsID(r);
  params.wedgeDetect = True;
  params.id.testsPerDepth = 10000;

  // Generate checker
  Stmt s <- mkModelChecker(checkForwardingRegFileWithReset(r.new_rst), params);
  mkAutoFSM(s);
endmodule