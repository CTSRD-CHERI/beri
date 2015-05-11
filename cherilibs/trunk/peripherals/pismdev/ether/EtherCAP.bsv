/*-
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2011 SRI International
 * Copyright (c) 2011 Jonathan Woodruff
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
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

/*
 * CHERI network MAC model for simulation
 * ======================================
 * Based on a C peripherial tymplate by:
 * Simon Moore, Aug 2011
 */

package EtherCAP;

//import MIPS::*;
import FIFO::*;
import SpecialFIFOs::*;
import GetPut::*;
import ClientServer::*;
import Avalon2ClientServer::*;
import StmtFSM::*;

import "BDPI" function ActionValue#(Int#(32)) cheri_net_handler(Int#(32) addr, Int#(32) data, Int#(32) read_notwrite);

`define word_address_width 3

interface EtherCAPTemplate_Ifc;
   interface Server#(MemAccessPacketT#(`word_address_width),ReturnedDataT) server;
   method Bool interrupt;
endinterface


module mkEtherCAP(EtherCAPTemplate_Ifc);
   PulseWire ipw <- mkPulseWire;
   FIFO#(MemAccessPacketT#(`word_address_width)) req <- mkLFIFO;
   FIFO#(Maybe#(AvalonWordT)) res <- mkBypassFIFO;

   rule communicate_with_c;
      let r = req.first;
      req.deq;
      // send request to C event handler
      let rtn <- cheri_net_handler(
				      unpack(pack(extend(r.addr))),
				      unpack(pack(r.data)),
				      r.rw==MemRead ? 1 : 0);
      if(r.rw==MemRead)
         res.enq(tagged Valid unpack(pack(rtn)));
   endrule

   method Bool interrupt;
      return ipw;
   endmethod

   interface Server server;
      interface request = toPut(req);
      interface response = toGet(res);
   endinterface
endmodule


/*****************************************************************************
 Test the template
 *****************************************************************************/

module mkTestBench(Empty);
	Reg#(UInt#(32)) j <- mkReg(0);      // loop counter
	Reg#(UInt#(32)) numerr <- mkReg(0); // error counter

	// instantiate design under test
	EtherCAPTemplate_Ifc dut <- mkEtherCAP;

	// state machine with test sequence
	Stmt test_seq =
	(seq
		action
			$display("Starting the testbench");
		endaction

		/* ID REV testing */
		action
			dut.server.request.put(MemAccessPacketT{
				rw: MemRead, addr: truncate(32'h50), data: 0
			});
		endaction
		action
			let r <- dut.server.response.get();
			let rtn = fromMaybe(0,r);
			
			$display("%05t; got %d, passed:%d", $time, rtn, rtn == (32'h01150000));
		endaction

		/* Byte testing register */
		action
			dut.server.request.put(MemAccessPacketT{
				rw: MemRead, addr: truncate(32'h64), data: 0
			});
		endaction
		action
			let r <- dut.server.response.get();
			let rtn = fromMaybe(0,r);
			
			$display("%05t; got %d, passed:%d", $time, rtn, rtn == (32'h87654321));
		endaction

		/* GP timer configuration and count */
		action
			dut.server.request.put(MemAccessPacketT{
				rw: MemRead, addr: truncate(32'h8c), data: 0
			});
		endaction
		action
			let r <- dut.server.response.get();
			let rtn = fromMaybe(0,r);
			
			$display("%05t; got %d, passed:%d", $time, rtn, rtn == (32'h0000ffff));
		endaction

		/* XX table driven approach necessary for Write/Read-back/Compare registers */
		seq
			/* RX configuration */
			action
				dut.server.request.put(MemAccessPacketT{
					rw: MemWrite, addr: truncate(32'h6c), data: 123
				});
			endaction
			action
				dut.server.request.put(MemAccessPacketT{
					rw: MemRead, addr: truncate(32'h6c), data: 0
				});
			endaction
			action
				let r <- dut.server.response.get();
				let rtn = fromMaybe(0,r);
				
				$display("%05t; got %d, passed:%d", $time, rtn, rtn == (32'd123));
			endaction
		endseq

		/* CSR register testing */
		for (j <= 0; j < 16; j <= j + 1) seq
			action
				/*
				 * Write a register number to CSR index register 0xa4
				 */
				dut.server.request.put(MemAccessPacketT{
					rw: MemWrite, addr: truncate(32'ha4), data: truncate(j)
				});
			endaction
			action
				/*
				 * Write a data to the register which we've just
				 * addressed
				 */
				dut.server.request.put(MemAccessPacketT{
					rw: MemWrite, addr: truncate(32'ha8), data: (32'hc0dec0de + j)
				});
			endaction
			action
				/* 
				 * Write a register number once again, since we want to
				 * read the value back
				 */
				dut.server.request.put(MemAccessPacketT{
					rw: MemWrite, addr: truncate(32'ha4), data: truncate(j)
				});
			endaction
			action
				/* Read the data back */
				let r <- dut.server.response.get();
				let rtn = fromMaybe(0,r);
				
				$display("%05t; got %d, passed:%d", $time, rtn, rtn == (32'hc0dec0de + j));
			endaction
		endseq

		/* Write a data to the MAC. */
		action
			/*
			 * TX command A: first data segment (1<<12), last data segment (1<<13)
			 * and data length (32'hff==255 bytes).
			 */
			dut.server.request.put(MemAccessPacketT{ rw: MemWrite,
				addr: truncate(32'h20), data: truncate(1<<12 | 1<<13 | 32'hff)});
		endaction
		action
			/*
			 * TX command B: we only repeat the data length == 255 bytes (32'hff)
			 */
			dut.server.request.put(MemAccessPacketT{ rw: MemWrite,
				addr: truncate(32'h20), data: truncate(32'hff) });
		endaction
		for (j <= 0; j < 255 ; j <= j + 1) seq
			action
				/*
				 * Enqueue 255 bytes of data
				 */
				dut.server.request.put(MemAccessPacketT{ rw: MemWrite,
					addr: truncate(32'h20), data: truncate(j) });
			endaction
		endseq

		if (numerr == 0)
			$display("%05t: The End - ALL PASSED",$time);
		else
			$display("%05t: The End - FAILED with %d errors",$time,numerr);
	endseq);

	let test_seq_FSM <- mkAutoFSM(test_seq);

endmodule

endpackage
