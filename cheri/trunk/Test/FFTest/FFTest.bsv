/*
 * Copyright 2015 Matthew Naylor
 * Copyright 2016 Jonathan Woodruff
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

import FF   :: *;
import StmtFSM   :: *;
import BlueCheck :: *;
import GetPut    :: *;
import FIFO      :: *;
import FIFOF     :: *;
import Clocks    :: *;

module [BlueCheck] ffCheck#(Reset r) ();
  FF#(Bit#(4), 4)   ff   <- mkFF();
  FIFO#(Bit#(4))    fifo <- mkSizedFIFO(4);
  
  equiv("enq",   ff.enq,   fifo.enq);
  equiv("first", ff.first, fifo.first);
  equiv("deq",   ff.deq,   fifo.deq);
endmodule

// Iterative deepening version
module [Module] testFFCheck ();
  Clock clk <- exposeCurrentClock;
  MakeResetIfc r <- mkReset(0, True, clk);
  //blueCheckID(checkForwardingRegFileWithReset(r.new_rst), r);
  
  // BlueCheck parameters
  BlueCheck_Params params = bcParamsID(r);
  params.wedgeDetect = True;
  params.id.testsPerDepth = 10000;

  // Generate checker
  Stmt s <- mkModelChecker(ffCheck(r.new_rst), params);
  mkAutoFSM(s);
endmodule
