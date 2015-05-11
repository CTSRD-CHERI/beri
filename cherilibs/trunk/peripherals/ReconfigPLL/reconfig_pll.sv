/*-
 * Copyright (c) 2014 Simon W. Moore
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
 *
 *****************************************************************************

 reconfig_pll
 ============
 
 This is a Qsys peripheral wrapper providing an interface to a
 reconfigurable PLL.  It instantitates ALTPLL_RECONFIG which provides
 a cache of the PLL parameters and when triggered it the writes them
 to the ALTPLL using a proprietary serial interface.  ALTPLL_RECONFIG
 also resets the ALTPLL post configuration.
 
 This module has the following memory map.
 
 All addresses refer to 32-bit little endian words.  Byte addressing is
 not supported.
 
 The lower address bits have the following meaning:
   bits 1-0 are always zero (word aligned)
   bits 5-2 is the counter_type
   bits 8-6 is the counter_parameter
   bit  9   when =1 for a write it causes the pll parameters to be written
            to the PLL.  When =1 and reading, it returns busy=0xB, done=0xD
 
 counter_type and counter_parameters are defined in Altera's
 ALTPLL_RECONFIG Users Guide:
 http://www.altera.co.uk/literature/ug/ug_altpll_reconfig.pdf

 For Stratix IV parts (e.g. on the DE4 board) the following
 counter_parameters are particularly useful:
   0  =  n
   1  =  m
   4  =  c0
 
 The output frequency clock c0 is given by:
   fout_c0 = (n * fin) / (m * c0)
 
 For each of these counter_parameters, the following counter_types
 need to be set:
   0  =  high_count (9-bits)
   1  =  low_count  (9-bits)
   4  =  bypass     (1-bit)
   5  =  odd_count  (1-bit)
 
 for a given required value v (where v>0):
   high_count = (v+1)/2
   low_count  = v - high_count
   bypass     = (v==1) ? 1 : 0;
   odd_count  = v & 0x1

 Writing the parameters to the ALTPLL
 ------------------------------------
 
 Remember that after setting the above parameters in the
 ALTPLL_RECONFIG cache you need to trigger it to write them to the
 ALTPLL by writing some word of data (the data is irrelivant) to
 an address on this peripheral with address bit 9 set.

*/

/* REMOVE************************ 
 Top-level Verilog hook-up
 -------------------------

 The ALTPLL needs to be instantiated outside of Qsys, e.g. in the
 top-level Verilog file, e.g. based on video_pll.{mif,ppf,qip,v} in
 this directory which is setup as a left-or-right PLL (the HDMI is
 connected to pins on the right of the FPGA and the PLL type has to be
 specified because they have differing numbers of clock outputs):
 
 wire pll_areset;
 wire pll_configupdate;
 wire pll_scanclk;
 wire pll_scanclkena;
 wire pll_scandata;
 wire pll_locked;
 wire pll_scandataout;
 wire pll_scandone;

 video_pll video_pll_inst
   (
    .inclk0         (OSC_50_BANK6),
    .c0             (vidclk),
    .areset         (pll_areset),
    .configupdate   (pll_configupdate),
    .scanclk        (pll_scanclk),
    .scanclkena     (pll_scanclkena),
    .scandata       (pll_scandata),
    .locked         (pll_locked), // unused
    .scandataout    (pll_scandataout),
    .scandone       (pll_scandone)
   );

 If the conduit coe_pll_... is named reconfig_pll in Qsys then the following
 signals need to be connected from the Qsys instantiation in the top-level
 Verilog to the above video PLL:
 
   .reconfig_pll_areset       (pll_areset),
   .reconfig_pll_configupdate (pll_configupdate),
   .reconfig_pll_scanclk      (pll_scanclk),
   .reconfig_pll_scanclkena   (pll_scanclkena),
   .reconfig_pll_scandata     (pll_scandata),
   .reconfig_pll_scandataout  (pll_scandataout),
   .reconfig_pll_scandone     (pll_scandone)

 *****************************************************************************/

module reconfig_pll
  (
   // clock/reset
   input 	 csi_clk_clock,
   input 	 csi_clk_reset,
   // source clock pin (assumed to be 50MHz)
   input 	 csi_clkpin_clock,
   // reconfigurable clock output
   output 	 cso_reconfigclk_clock,
   output        cso_reconfigclk_reset_n, 	 
   // avalon memory-mapped slave (32-bit word addressed)
   input [7:0] 	 avs_address,
   input [31:0]  avs_writedata,
   output [31:0] avs_readdata,
   input 	 avs_read,
   input 	 avs_write,
   output 	 avs_waitrequest
   );

   // reset syncronizer
   reg [2:0]    pll_reset_sync;
   
   // wires to PLL to be configured
   wire         pll_scandataout;
   wire 	pll_scandone;
   wire 	pll_areset;
   wire 	pll_configupdate;
   wire 	pll_scanclk;
   wire 	pll_scanclkena;
   wire 	pll_scandata;
   wire 	pll_locked; // unused	

   wire   [8:0] reconfig_data_out;
   wire 	reconfig_busy;

   wire   reconfig_go    =  avs_address[7] && avs_write;
   wire   reconfig_write = !avs_address[7] && avs_write;
   wire   reconfig_read  = !avs_address[7] && avs_read;

   // report busy status (upper addresses) or reconfig data (lower addresses)
   assign avs_readdata = avs_address[7] ?
			 (reconfig_busy ? 32'h0B : 32'h0D) :
			 {23'd0, reconfig_data_out};

   // only wait on reconfigure module accesses
   assign avs_waitrequest = !avs_address[7] && reconfig_busy;
   
   // instantiate an instance of a ALTPLL_RECONFIG megafunction
   reconfig_megafunction_pll_reconfig reconfig_control_block
     (
      .clock            (csi_clk_clock),
      .reset            (csi_clk_reset),
      .pll_areset_in    (csi_clk_reset),
      .counter_param    (avs_address[6:4]),
      .counter_type     (avs_address[3:0]),
      .data_in          (avs_writedata[8:0]),
      .data_out         (reconfig_data_out),
      .read_param       (reconfig_read),
      .write_param      (reconfig_write),
      .busy             (reconfig_busy),
      .reconfig         (reconfig_go),
      .pll_scandataout  (pll_scandataout),
      .pll_scandone     (pll_scandone),
      .pll_areset       (pll_areset),  // used to reset PLL after reconfig
      .pll_configupdate (pll_configupdate),
      .pll_scanclk      (pll_scanclk),
      .pll_scanclkena   (pll_scanclkena),
      .pll_scandata     (pll_scandata)
      );

   reconfig_megafunction_pll reconfig_pll_inst
     (
      .inclk0         (csi_clkpin_clock),
      .c0             (cso_reconfigclk_clock),
      .areset         (pll_areset),
      .configupdate   (pll_configupdate),
      .scanclk        (pll_scanclk),
      .scanclkena     (pll_scanclkena),
      .scandata       (pll_scandata),
      .locked         (pll_locked),
      .scandataout    (pll_scandataout),
      .scandone       (pll_scandone)
      );

   wire   reset_synchronizer = !pll_locked || pll_areset;

   always_ff @(posedge cso_reconfigclk_clock or posedge reset_synchronizer)
     if(reset_synchronizer)
       pll_reset_sync <= 0;
     else
       pll_reset_sync <= {pll_reset_sync[1:0],1'b1};
   
   assign cso_reconfigclk_reset_n = pll_reset_sync[2];
   
endmodule // video_pll_config_avalonmm
