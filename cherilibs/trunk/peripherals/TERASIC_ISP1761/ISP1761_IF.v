//
// Copyright (c) 2012 Simon W. Moore
// Copyright (c) 2013 Jonathan Woodruff
// All rights reserved.
//
// This software was developed by SRI International and the University of
// Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
// ("CTSRD"), as part of the DARPA CRASH research programme.
//
// @BERI_LICENSE_HEADER_START@
//
// Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
// license agreements.  See the NOTICE file distributed with this work for
// additional information regarding copyright ownership.  BERI licenses this
// file to you under the BERI Hardware-Software License, Version 1.0 (the
// "License"); you may not use this file except in compliance with the
// License.  You may obtain a copy of the License at:
//
//   http://www.beri-open-systems.org/legal/license-1-0.txt
//
// Unless required by applicable law or agreed to in writing, Work distributed
// under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied.  See the License for the
// specific language governing permissions and limitations under the License.
//
// @BERI_LICENSE_HEADER_END@
//


module ISP1761_IF(
// SWM: clock and reset keep Qsys happy though they are not used
	csi_clk,
	csi_reset_n,
                    
// host controller slave port                  
	s_cs_n,
	s_address,
	s_write_n,
	s_writedata,
	s_read_n,
	s_readdata,
	s_hc_irq,
// device controller
	s_dc_irq,
	s_dc_readdata,

// exported to ISP1761 I/O pins
	CS_N,
	WR_N,
	RD_N,
	D,
	A,
	DC_IRQ,
	HC_IRQ,
	DC_DREQ,
	HC_DREQ,
	DC_DACK,
	HC_DACK
);


  input         csi_clk;
  input         csi_reset_n;
  
  // slave host controller
  input         s_cs_n;
  input [15:0]  s_address;
  input         s_write_n;
  input [31:0]  s_writedata;
  input         s_read_n;
  output [31:0] s_readdata;
  output        s_hc_irq;

  // dummy (don't support device controller)
  output        s_dc_irq;
  output [31:0] s_dc_readdata;

  // exported
  output        CS_N;					
  output        WR_N;
  output        RD_N;
  inout [31:0]  D;
  output [17:1] A;
  input         DC_IRQ;              
  input         HC_IRQ;
  input         DC_DREQ;              
  input         HC_DREQ;              
  output        DC_DACK;              
  output        HC_DACK;

  assign CS_N = s_cs_n;
  assign WR_N = s_write_n;
  assign RD_N = s_read_n;
  assign A = {s_address[15:0],1'b0};
  assign s_hc_irq =  HC_IRQ;
  assign s_dc_irq =  DC_IRQ;

  assign D = (!s_cs_n & s_read_n) ? s_writedata : 32'hzzzzzzzz;
  assign s_readdata = D;

endmodule
