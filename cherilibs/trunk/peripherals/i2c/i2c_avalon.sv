//
// Copyright (c) 2012 Jonathan Woodruff
// Copyright (c) 2012 Simon W. Moore
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


/////////////////////////////////////////////////////////////////////
////                                                             ////
////  Avalon compliant I2C Master controller Top-level           ////
////                                                             ////
////                                                             ////
////  Author: Jonathan Woodruff                                  ////
////    jdw57@cam.ac.uk                                          ////
////  Updated by Simon Moore to use Qsys prefered port names     ////
////  and move to SystemVerilog.  Fixed timing issues, etc.      ////
/////////////////////////////////////////////////////////////////////

`include "i2c_master_top.v"

module i2c_avalon
  (
   // avalon signals
   input        csi_clk,            // master clock input
   input        csi_reset_n,        // synchronous active low reset
   input  [2:0] avs_address,        // address bits
   input  [7:0] avs_writedata,      // databus input
   output [7:0] avs_readdata,       // databus output
   input        avs_read,           // active low read signal
   input        avs_write,          // active low write signal
   output       avs_waitrequest,    // bus wait for valid data
   output       avs_irq,            // interrupt request signal output
  
   // I2C signals
   // i2c clock line
   output       coe_i2c_scl_oe_n,    // SCL-line output enable (active low)
   output       coe_i2c_scl_o,       // SCL-line output (always low)
   input        coe_i2c_scl_i,       // SCL-line input to check pull-up status

   // i2c data line
   input        coe_i2c_sda_i,       // SDA-line input
   output       coe_i2c_sda_oe_n,    // SDA-line output enable (active low)
   output       coe_i2c_sda_o        // SDA-line output (always low)
   );

  //
  // variable declarations
  //

  // wishbone signals
  wire  wb_we_i;      // write enable input
  wire  wb_stb_i;     // stobe/core select signal
  wire  wb_cyc_i;     // valid bus cycle input
  wire  wb_ack_o;     // bus cycle acknowledge output

  //
  // module body
  //

  // writes happen instantly and reads take one cycle:
  reg   prev_waitreq;
  assign avs_waitrequest = avs_read && !prev_waitreq;
  always_ff @(posedge csi_clk)
    prev_waitreq <= avs_waitrequest;

  wire device_enabled = avs_read || avs_write;

  // instantiate wishbone i2c controller
  i2c_master_top i2c_controller (
    .wb_clk_i       ( csi_clk ),
    .wb_rst_i       ( !csi_reset_n ),
    .arst_i         ( csi_reset_n ),
    .wb_adr_i       ( avs_address ),
    .wb_dat_i       ( avs_writedata ),
    .wb_dat_o       ( avs_readdata ),
    .wb_we_i        ( avs_write ),
    .wb_stb_i       ( device_enabled ),
    .wb_cyc_i       ( device_enabled ),
    .wb_ack_o       (  ),
    .wb_inta_o      ( avs_irq ),
    .scl_pad_i      ( coe_i2c_scl_i ),
    .scl_pad_o      ( coe_i2c_scl_o ),
    .scl_padoen_o   ( coe_i2c_scl_oe_n ),
    .sda_pad_i      ( coe_i2c_sda_i ),
    .sda_pad_o      ( coe_i2c_sda_o ),
    .sda_padoen_o   ( coe_i2c_sda_oe_n )
  );

endmodule
