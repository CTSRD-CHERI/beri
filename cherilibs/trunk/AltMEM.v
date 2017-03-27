/*-
 * Copyright (c) 2016 Jonathan Woodruff
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
 *  http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 */

`ifdef BSV_ASSIGNMENT_DELAY
`else
 `define BSV_ASSIGNMENT_DELAY
`endif

// Dual-Ported BRAM
module AltMEM(RST,
				 CLK,
				 CLK_GATE,
             ADDRR,
             REN,
             DO,
             ADDRW,
             DI,
             WEN,
             EN_UNUSED2
             );

   // synopsys template
   parameter                      ADDR_WIDTH = 'd 1;
   parameter                      DATA_WIDTH = 'd 1;
   parameter                      MEMSIZE    = 'd 1;
   
	input                          RST;
   input                          CLK;
   input                          CLK_GATE;
   input                          REN;
   input [ADDR_WIDTH-1:0]         ADDRR;
   output [DATA_WIDTH-1:0]        DO;

   input                          WEN;
   input [ADDR_WIDTH-1:0]         ADDRW;
   input [DATA_WIDTH-1:0]         DI;
	
	input                          EN_UNUSED2;

	altsyncram	altsyncram_component (
				.clock0 (CLK),
				.address_a (ADDRW),
				.data_a (DI),
				.wren_a (WEN),
				.address_b (ADDRR),
				.rden_b (REN),
				.q_b (DO)
				// All below are unused
				//.aclr0 (1'b0),
				//.aclr1 (1'b0),
				//.addressstall_a (1'b0),
				//.addressstall_b (1'b0),
				//.byteena_a (1'b1),
				//.byteena_b (1'b1),
				//.clock1 (1'b1),
				//.clocken0 (1'b1),
				//.clocken1 (1'b1),
				//.clocken2 (1'b1),
				//.clocken3 (1'b1),
				//.data_b (1'b1),
				//.eccstatus (),
				//.q_a (),
				//.rden_a (1'b1),
				//.wren_b (1'b0)
      );
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.intended_device_family = "Stratix IV",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = MEMSIZE,
		altsyncram_component.numwords_b = MEMSIZE,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.rdcontrol_reg_b = "CLOCK0",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.widthad_a = ADDR_WIDTH,
		altsyncram_component.widthad_b = ADDR_WIDTH,
		altsyncram_component.width_a = DATA_WIDTH,
		altsyncram_component.width_b = DATA_WIDTH;

endmodule
	

