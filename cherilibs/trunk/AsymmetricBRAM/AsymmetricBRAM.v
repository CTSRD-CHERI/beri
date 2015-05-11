//
// Copyright (c) 2013 Alexandre Joannou
// Copyright (c) 2014 A. Theodore Markettos
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


module AsymmetricBRAM(
	CLK,
	RADDR,
	RDATA,
	REN,
	WADDR,
	WDATA,
	WEN
);
	
	parameter	PIPELINED   = 'd 0;
	parameter	FORWARDING  = 'd 0;
	parameter	WADDR_WIDTH = 'd 0;
	parameter	WDATA_WIDTH = 'd 0;
	parameter	RADDR_WIDTH = 'd 0;
	parameter	RDATA_WIDTH = 'd 0;
	parameter	MEMSIZE     = 'd 1;
	parameter	REGISTERED  = (PIPELINED  == 0) ? "UNREGISTERED":"CLOCK0";
	
	input   CLK;
	input	[RADDR_WIDTH-1:0]   RADDR;
	output	[RDATA_WIDTH-1:0]   RDATA;
	input	REN;
	input	[WADDR_WIDTH-1:0]   WADDR;
	input	[WDATA_WIDTH-1:0]   WDATA;
	input   WEN;
	
	/*
	wire    [RDATA_WIDTH-1:0]   BRAM_RDATA;
	wire    [RADDR_WIDTH-1:0]   RADDR_MUXED;
	reg     [RADDR_WIDTH-1:0]   LAST_RADDR;
	reg     [WDATA_WIDTH-1:0]   LAST_WDATA;
	reg     [WADDR_WIDTH-1:0]   LAST_WADDR;
	
	always @(posedge CLK) begin
		if (WEN) begin
			LAST_WADDR <= WADDR;
			LAST_WDATA <= WDATA;
		end
		LAST_RADDR <= RADDR_MUXED;
	end
	
	assign  RADDR_MUXED = (REN) ? RADDR : LAST_RADDR;
	assign  RDATA = (LAST_RADDR==LAST_WADDR) ? LAST_WDATA : BRAM_RDATA;
	*/
	
	altsyncram	altsyncram_component (
		.address_a (WADDR),
		.clock0 (CLK),
		.data_a (WDATA),
		.rden_b (REN),
		.wren_a (WEN),
		.address_b (RADDR),
		.q_b (RDATA),
		.aclr0 (1'b0),
		.aclr1 (1'b0),
		.addressstall_a (1'b0),
		.addressstall_b (1'b0),
		.byteena_a (1'b1),
		.byteena_b (1'b1),
		.clock1 (1'b1),
		.clocken0 (1'b1),
		.clocken1 (1'b1),
		.clocken2 (1'b1),
		.clocken3 (1'b1),
		.data_b ({32{1'b1}}),
		.eccstatus (),
		.q_a (),
		.rden_a (1'b1),
		.wren_b (1'b0));
	defparam
		altsyncram_component.intended_device_family = "Cyclone IV E",
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.indata_reg_b = "CLOCK0",
		altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = MEMSIZE / (WDATA_WIDTH/RDATA_WIDTH),
		altsyncram_component.numwords_b = MEMSIZE,
		altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = REGISTERED,
		altsyncram_component.power_up_uninitialized = "TRUE",
		altsyncram_component.ram_block_type = "M9K",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.widthad_a = WADDR_WIDTH,
		altsyncram_component.widthad_b = RADDR_WIDTH,
		altsyncram_component.width_a = WDATA_WIDTH,
		altsyncram_component.width_b = RDATA_WIDTH,
		altsyncram_component.width_byteena_a = 1,
		altsyncram_component.width_byteena_b = 1;
endmodule
