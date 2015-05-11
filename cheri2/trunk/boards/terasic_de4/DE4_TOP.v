//
// Copyright (c) 2012-2013 Jonathan Woodruff
// Copyright (c) 2013 Bjoern A. Zeeb
// Copyright (c) 2014 A. Theodore Markettos
// Copyright (c) 2014 Robert M. Norton
// All rights reserved.
//
// This software was developed by SRI International and the University of
// Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
// ("CTSRD"), as part of the DARPA CRASH research programme.
//
// This software was developed by SRI International and the University of
// Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
// ("MRC2"), as part of the DARPA MRC research programme.
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


`define	ENABLE_LED
`define	ENABLE_BUTTONS
`define	ENABLE_ETHERNET
`define	ENABLE_SDCARD
`define	ENABLE_UART
`define	ENABLE_DDR2_1
`define	ENABLE_DIP
`define ENABLE_SLIDE
`define	ENABLE_SEG
`define	ENABLE_TEMP
`define	ENABLE_CSENSE
`define ENABLE_FLASH
`define	ENABLE_SSRAM
`define	ENABLE_USB
`define	ENABLE_HDMI
`define	ENABLE_MTL

`ifndef ENABLE_DDR2_1
`ifndef ENABLE_DDR2_2
`define DISABLE_TERMINATION
`endif
`endif

`ifndef ENABLE_FLASH
`ifndef ENABLE_SSRAM
`define DISABLE_FSM
`endif
`endif

module DE4_BERI (

	////// clock inputs
	//input			GCLKIN,
	//output		GCLKOUT_FPGA,
	//inout		[2:0]	MAX_CONF_D,
	//output	[2:0]	MAX_PLL_D,
	input 	 		OSC_50_Bank2,
	input			OSC_50_Bank3,
	input			OSC_50_Bank4,
	//input			OSC_50_Bank5,
	//input			OSC_50_Bank6,
	//input   		OSC_50_Bank7,
	//input        		PLL_CLKIN_p,
	
`ifdef ENABLE_LED
	output 	[7:0]	LED,	// 8x LEDs
`endif

`ifdef ENABLE_BUTTONS
	input		[3:0]	BUTTON,	// 4x buttons
`endif
   	input			CPU_RESET_n,
	//inout			EXT_IO,
	
`ifdef ENABLE_ETHERNET
	////// Ethernet MAC x 4
	input		[3:0]	ETH_INT_n,
	output		[3:0]	ETH_MDC,
	inout		[3:0]	ETH_MDIO,
	output			ETH_RST_n,
	input		[3:0]	ETH_RX_p,
	output		[3:0]	ETH_TX_p,
`endif

`ifdef ENABLE_SDCARD
	////// SD card socket
	output 	 	SD_CLK,
	inout			SD_CMD,
	inout		[3:0]	SD_DAT,
	input			SD_WP_n,
`endif

`ifdef ENABLE_UART
	////// UART
	output			UART_TXD,
	input			UART_CTS,
	input			UART_RXD,
	output			UART_RTS,
`endif

`ifdef ENABLE_DDR2_1
	////// DDR2 SODIMM 1
	output		[15:0]	M1_DDR2_addr,
	output		[2:0]	M1_DDR2_ba,
	output			M1_DDR2_cas_n,
	output		[1:0]	M1_DDR2_cke,
	inout		[1:0]	M1_DDR2_clk,
	inout		[1:0]	M1_DDR2_clk_n,
	output		[1:0]	M1_DDR2_cs_n,
	output		[7:0]	M1_DDR2_dm,
	inout		[63:0]	M1_DDR2_dq,
	inout		[7:0]	M1_DDR2_dqs,
	inout		[7:0]	M1_DDR2_dqsn,
	output		[1:0]	M1_DDR2_odt,
	output			M1_DDR2_ras_n,
	output		[1:0]	M1_DDR2_SA,
	output			M1_DDR2_SCL,
	inout			M1_DDR2_SDA,
	output			M1_DDR2_we_n,
`endif

`ifdef ENABLE_DDR2_2
	////// DDR2 SODIMM 2
	output		[15:0]	M2_DDR2_addr,
	output		[2:0]	M2_DDR2_ba,
	output			M2_DDR2_cas_n,
	output		[1:0]	M2_DDR2_cke,
	inout		[1:0]	M2_DDR2_clk,
	inout		[1:0]	M2_DDR2_clk_n,
	output		[1:0]	M2_DDR2_cs_n,
	output		[7:0]	M2_DDR2_dm,
	inout		[63:0]	M2_DDR2_dq,
	inout		[7:0]	M2_DDR2_dqs,
	inout		[7:0]	M2_DDR2_dqsn,
	output		[1:0]	M2_DDR2_odt,
	output			M2_DDR2_ras_n,
	output		[1:0]	M2_DDR2_SA,
	output			M2_DDR2_SCL,
	inout			M2_DDR2_SDA,
	output			M2_DDR2_we_n,
`endif

`ifndef DISABLE_TERMINATION
	// termination for DDR2 DIMMs
	input			termination_blk0_rup_pad,
	input			termination_blk0_rdn_pad,
`endif
	
`ifdef	ENABLE_DIP
	input		[7:0]	SW,		// 8x DIP switches
`endif

`ifdef	ENABLE_SLIDE
	input [3:0] 	 SLIDE_SW,	// 4x slide switches
`endif
	
`ifdef ENABLE_SEG
	// 2x 7-segment displays
	output		[6:0]	SEG0_D,
	output			SEG0_DP,
	output		[6:0]	SEG1_D,
	output			SEG1_DP,
`endif

`ifdef	ENABLE_TEMP
	// temperature sensors
	input			TEMP_INT_n,
	output			TEMP_SMCLK,
	inout			TEMP_SMDAT,
`endif

`ifdef	ENABLE_CSENSE
	// current sensors
	output			CSENSE_ADC_FO,
	output		[1:0]	CSENSE_CS_n,
	output			CSENSE_SCK,
	output			CSENSE_SDI,
	input			CSENSE_SDO,
`endif
	
	output			FAN_CTRL,	// fan control
	
`ifndef DISABLE_FSM
	// flash and SRAM shared data bus
	output		[25:1]	FSM_A,
	inout		[15:0]	FSM_D,
`endif

`ifdef	ENABLE_FLASH
	// Flash memory
	output			FLASH_ADV_n,
	output			FLASH_CE_n,
	output			FLASH_CLK,
	output			FLASH_OE_n,
	output			FLASH_RESET_n,
	input			FLASH_RYBY_n,
	output			FLASH_WE_n,
`endif
	
`ifdef	ENABLE_SSRAM
	// synchronous SRAM
	output			SSRAM_ADV,
	output			SSRAM_BWA_n,
	output			SSRAM_BWB_n,
	output			SSRAM_CE_n,
	output			SSRAM_CKE_n,
	output			SSRAM_CLK,
	output			SSRAM_OE_n,
	output			SSRAM_WE_n,
`endif
	
	// HSMC port A and B
`ifdef	ENABLE_HDMI
	// HDMI interface board on HSMC port A
	//inout                     	HDMI_SDA,
	//output                    	HDMI_SCL,
	output		[11:0]	HDMI_TX_RD,
	output		[11:0]	HDMI_TX_GD,
	inout			HDMI_TX_PCSCL,
	inout			HDMI_TX_PCSDA,
	output			HDMI_TX_RST_N,
	input			HDMI_TX_INT_N,
	output		[3:0]	HDMI_TX_DSD_L,
	output		[3:0]	HDMI_TX_DSD_R,
	output		[11:0]	HDMI_TX_BD,
	output			HDMI_TX_PCLK,
	output			HDMI_TX_DCLK,
	output			HDMI_TX_SCK,
	output			HDMI_TX_WS,
	output			HDMI_TX_MCLK,
	output		[3:0]	HDMI_TX_I2S,
	output			HDMI_TX_DE,
	output			HDMI_TX_VS,
	output			HDMI_TX_HS,
	output			HDMI_TX_SPDIF,
	inout			HDMI_TX_CEC,
`endif
	
// GPIO port 0
	input		[31:0]	GPIO0_D,

`ifdef ENABLE_USB	
	output		[17:1]	OTG_A,
	output			OTG_CS_n,
	inout		[31:0]	OTG_D,
	output			OTG_DC_DACK,
	input			OTG_DC_DREQ,
	input			OTG_DC_IRQ,
	output			OTG_HC_DACK,
	input			OTG_HC_DREQ,
	input			OTG_HC_IRQ,
	output			OTG_OE_n,
	output			OTG_RESET_n,
	output			OTG_WE_n,
`endif
	
`ifdef	ENABLE_MTL
	// GPIO port 1 connect to MTL capacitive touch screen
	output			mtl_dclk,
	output		[7:0]	mtl_r,
	output		[7:0]	mtl_g,
	output		[7:0]	mtl_b,
	output			mtl_hsd,
	output			mtl_vsd,
	output			mtl_touch_i2cscl,
	inout			mtl_touch_i2csda,
	input			mtl_touch_int
`endif

`ifdef	ENABLE_PCIE
	,
	//PCI Express
	input			PCIE_PREST_n,
	input			PCIE_REFCLK_p,
	//input     		HSMA_REFCLK_p,
	input		[3:0]	PCIE_RX_p,
	input			PCIE_SMBCLK,
	inout			PCIE_SMBDAT,
	output		[3:0]	PCIE_TX_p,
	output			PCIE_WAKE_n
`endif

);

	wire     global_reset_n;
	wire     enet_reset_n;

	//// Ethernet
	wire	 enet_mdc;
	wire 	 enet_mdio_in;
	wire 	 enet_mdio_oen;
	wire 	 enet_mdio_out;
	wire 	 enet_refclk_125MHz;

	wire 	 lvds_rxp;
	wire 	 lvds_txp;

	wire 	 enet1_mdc;
	wire 	 enet1_mdio_in;
	wire 	 enet1_mdio_oen;
	wire 	 enet1_mdio_out;

	wire 	 lvds_rxp1;
	wire 	 lvds_txp1;

	// Assign outputs that are not used to 0
	//assign MAX_PLL_D = 3'b0;
	//assign ETH_MDC[3:1] = 3'b0;
	assign	M1_DDR2_SA = 1'b0;
	assign	CSENSE_CS_n = 1'b0;
	assign CSENSE_ADC_FO = 1'b0;
	assign CSENSE_SCK = 1'b0;
	assign CSENSE_SDI = 1'b0;
	//assign GCLKOUT_FPGA = 1'b0;
	assign M1_DDR2_SCL = 1'b0;

	//// Ethernet
	assign	ETH_RST_n			= rstn;

	assign ETH_TX_p[3:2]       		= 2'b0;
	assign	lvds_rxp			= ETH_RX_p[0];
	assign	ETH_TX_p[0]			= lvds_txp;

	assign	lvds_rxp1			= ETH_RX_p[1];
	assign	ETH_TX_p[1]			= lvds_txp1;

	assign	enet_mdio_in			= ETH_MDIO[0];
	assign	enet1_mdio_in			= ETH_MDIO[1];

	assign	ETH_MDIO[0]			= (!enet_mdio_oen ? enet_mdio_out : 1'bz);
	assign	ETH_MDIO[1]			= (!enet1_mdio_oen ? enet1_mdio_out : 1'bz);
	// Allow the other two tri-state interfaces to float.
	assign	ETH_MDIO[2]			= 1'bz;
	assign	ETH_MDIO[3]			= 1'bz;

	assign	ETH_MDC[0]			= enet_mdc;
	assign	ETH_MDC[1]			= enet1_mdc;
	// Set unused interface clocks to high.
	assign	ETH_MDC[2]			= 1'b1;
	assign	ETH_MDC[3]			= 1'b1;

	wire clk100;
	wire [7:0] LED_n;

	assign LED = ~LED_n;

	// === Ethernet clock PLL
	pll_125 pll_125_ins (
		.inclk0(OSC_50_Bank2),
		.c0(enet_refclk_125MHz)
	);

`ifdef ENABLE_PCIE
	wire clk125;

	//PCI Express clock
	pll_125 pll_125_pcie (
		.inclk0(OSC_50_Bank2),
		.c0(clk125)
	);

	assign reconfig_clk = OSC_50_Bank3;
	wire reconfig_fromgxb;
	wire reconfig_togxb;
	wire reconfig_busy;

	altgx_reconfig altgx_reconfig_pcie (
		.reconfig_clk(reconfig_clk),
		.reconfig_fromgxb(reconfig_fromgxb),
		.busy(reconfig_busy),
		.reconfig_togxb(reconfig_togxb)
	);
`endif

	wire qsys_sysclk;
	wire qsys_sysreset_n;

	//wire sramClk;
	assign SSRAM_CLK = qsys_sysclk;

	(* keep = 1 *) wire clk27;
	display_pll display_pll_ins (
		.inclk0(OSC_50_Bank2),
		.c0(clk27)
	);
				
	assign HDMI_TX_PCLK = clk27;
 
	// synchronize reset signal
	reg           rstn, rstn_metastable;
	always @(posedge OSC_50_Bank2)
	begin
	  rstn_metastable <= CPU_RESET_n && GPIO0_D[2];
	  rstn <= rstn_metastable;
	end

	reg           rstn100, rstn100_metastable;
	always @(posedge qsys_sysclk)
	begin
	  rstn100_metastable <= CPU_RESET_n && GPIO0_D[2];
	  rstn100 <= rstn100_metastable;
	end

	(* noprune *) reg rstn27;
	reg rstn27sample;
 
	always @(posedge clk27)
	begin
		rstn27sample <= rstn;
		rstn27 <= rstn27sample;
	end

	reg [7:0] SW_P;
	always @(posedge OSC_50_Bank2) SW_P <= ~SW;  // positive version of DIP switches

	assign SEG1_DP = ~1'b0;
	assign SEG0_DP = ~1'b0;

	reg [3:0]   slide_sw_metastable, slide_sw_sync;
	always @(posedge OSC_50_Bank2)
	 begin
		slide_sw_metastable <= SLIDE_SW;
		slide_sw_sync <= slide_sw_metastable;
	 end

	//  assign PCIE_WAKE_n = 1'b0;
	//  assign PCIE_SMBDATA = 1'bz;

	/* signals for the old Terasic resistive touch screen (currently unused)
	wire [7:0] vga_R, vga_G, vga_B;
	wire       vga_DEN, vga_HD, vga_VD;

	assign vga_DEN = 1'b0;
	assign vga_HD = 1'b0;
	assign vga_VD = 1'b0;
	assign vga_R = 8'd0;
	assign vga_G = 8'd0;
	assign vga_B = 8'd0;

	assign lcdtouchLTM_R = vga_R;
	assign lcdtouchLTM_G = vga_G;
	assign lcdtouchLTM_B = vga_B;
	assign lcdtouchLTM_DEN = vga_DEN;
	assign lcdtouchLTM_HD = vga_HD;
	assign lcdtouchLTM_VD = vga_VD;

	assign lcdtouchLTM_GREST = rstn27;
	assign lcdtouchLTM_NCLK = clk27;

	assign lcdtouchLTM_SCEN = 1'b1;
	assign lcdtouchLTM_ADC_DCLK = 1'b1;
	assign lcdtouchLTM_ADC_DIN = 1'b1;*/
	 
	// clock for multitouch screen
	assign mtl_dclk      = clk27;


	(* keep = 1 *) wire        ssram_data_outen;
	(* keep = 1 *) wire [15:0] ssram_data_out;


	// instantiate the touch screen controller provided by Terasic (encrypted block)
	reg  touch_ready_0;
	reg [9:0] touch_x1_0, touch_x2_0;
	reg [8:0] touch_y1_0, touch_y2_0;
	reg [1:0] touch_count_0;
	reg [7:0] touch_gesture_0;

	reg  touch_ready_1;
	reg [9:0] touch_x1_1, touch_x2_1;
	reg [8:0] touch_y1_1, touch_y2_1;
	reg [1:0] touch_count_1;
	reg [7:0] touch_gesture_1;

	wire  touch_ready_2;
	wire [9:0] touch_x1_2, touch_x2_2;
	wire [8:0] touch_y1_2, touch_y2_2;
	wire [1:0] touch_count_2;
	wire [7:0] touch_gesture_2;
  
	i2c_touch_config touch(
		 .iCLK(OSC_50_Bank2),
		 .iRSTN(rstn),
		 .iTRIG(!mtl_touch_int), // note that this signal is inverted
		 .oREADY(touch_ready_2),
		 .oREG_X1(touch_x1_2),
		 .oREG_Y1(touch_y1_2),
		 .oREG_X2(touch_x2_2),
		 .oREG_Y2(touch_y2_2),
		 .oREG_TOUCH_COUNT(touch_count_2),
		 .oREG_GESTURE(touch_gesture_2),
		 .I2C_SCLK(mtl_touch_i2cscl),
		 .I2C_SDAT(mtl_touch_i2csda));

	// synchronize signals to qsys system clock
	always @(posedge qsys_sysclk)
		 begin
			touch_ready_1 <= touch_ready_2;
			touch_x1_1 <= touch_x1_2;
			touch_y1_1 <= touch_y1_2;
			touch_x2_1 <= touch_x2_2;
			touch_y2_1 <= touch_y2_2;
			touch_count_1 <= touch_count_2;
			touch_gesture_1 <= touch_gesture_2;
		
			touch_ready_0 <= touch_ready_1;
			touch_x1_0 <= touch_x1_1;
			touch_y1_0 <= touch_y1_1;
			touch_x2_0 <= touch_x2_1;
			touch_y2_0 <= touch_y2_1;
			touch_count_0 <= touch_count_1;
			touch_gesture_0 <= touch_gesture_1;
		 end
	// touch screen controller end
 
	wire                  i2c_scl_oe_n;
	wire                  i2c_scl_o;
	wire                  i2c_scl_i = HDMI_TX_PCSCL;
	wire                  i2c_sda_oe_n;
	wire                  i2c_sda_o;
	wire                  i2c_sda_i = HDMI_TX_PCSDA;
	// tristate buffers
	assign HDMI_TX_PCSCL = i2c_scl_oe_n==1'b0 ? i2c_scl_o : 1'bz;
	assign HDMI_TX_PCSDA = i2c_sda_oe_n==1'b0 ? i2c_sda_o : 1'bz;
	  
	//wire gen_sck;
	//wire gen_i2s;
	//wire gen_ws;
	  
	assign HDMI_TX_SCK = 1'b0;
	assign HDMI_TX_I2S = 4'b0;//{gen_i2s, gen_i2s, gen_i2s, gen_i2s};
	assign HDMI_TX_WS = 1'b0;//gen_ws;
	
	wire [31:0] otg_dout;
	assign OTG_D = (!OTG_CS_n & OTG_OE_n) ? otg_dout : 32'hzzzzzzzz;
	wire [16:0] otg_a_temp;
	assign OTG_A[17:1] = otg_a_temp[16:0];

	DE4_SOC DE4_SOC_inst(
		// 1) global signals:
		 .clk_50_clk(OSC_50_Bank2),
		 .clk_125_clk(enet_refclk_125MHz),
		 .reset_reset_n(rstn),
		 .sysclk_clk(qsys_sysclk),
		 //.sysreset_reset_n(qsys_sysreset_n),
		 .leds_external_connection_export(LED_n),

		// the_ddr2
		 .ddr2_global_reset_reset_n(),
		  .memory_mem_cke                                    (M1_DDR2_cke),                                    //               ddr2.cke
		  .memory_mem_ck_n                                   (M1_DDR2_clk_n),                                   //                   .ck_n
		  .memory_mem_cas_n                                  (M1_DDR2_cas_n),                                  //                   .cas_n
		  .memory_mem_dq                                     (M1_DDR2_dq),                                     //                   .dq
		  .memory_mem_dqs                                    (M1_DDR2_dqs),	  //                   .dqs
		  .memory_mem_odt                                    (M1_DDR2_odt),                                    //                   .odt
		  .memory_mem_cs_n                                   (M1_DDR2_cs_n),                                   //                   .cs_n
		  .memory_mem_ba                                     (M1_DDR2_ba),                                     //                   .ba
		  .memory_mem_dm                                     (M1_DDR2_dm),                                     //                   .dm
		  .memory_mem_we_n                                   (M1_DDR2_we_n),                                   //                   .we_n
		  .memory_mem_dqs_n                                  (M1_DDR2_dqsn),                                  //                   .dqs_n
		  .memory_mem_ras_n                                  (M1_DDR2_ras_n),                                  //                   .ras_n
		  .memory_mem_ck                                     (M1_DDR2_clk),                                     //                   .ck
		  .memory_mem_a                                      (M1_DDR2_addr),                                      //                   .a      
		  .oct_rup                          (termination_blk0_rup_pad),                          //                   .oct_rup
		  .oct_rdn                          (termination_blk0_rdn_pad),                          //                   .oct_rdn
							 
		          // ddr2 psd i2c
	//	.out_port_from_the_ddr2_i2c_scl(M1_DDR2_SCL),
	//	.out_port_from_the_ddr2_i2c_sa(M1_DDR2_SA),
	//	.bidir_port_to_and_from_the_ddr2_i2c_sda(M1_DDR2_SDA)                   

		// ---------------------------------------------------------------------
		// MAC (TSE) 0
		.mac_mac_mdio_mdc			(enet_mdc),		//                        mac_mac_mdio.mdc
		.mac_mac_mdio_mdio_in			(enet_mdio_in),		//                                    .mdio_in
		.mac_mac_mdio_mdio_out			(enet_mdio_out),	//                                    .mdio_out
		.mac_mac_mdio_mdio_oen			(enet_mdio_oen),	//                                    .mdio_oen
		//.mac_mac_misc_xon_gen,		(/* input */)		//                        mac_mac_misc.xon_gen
		//.mac_mac_misc_xoff_gen,		(/* input */)		//                                    .xoff_gen
		//.mac_mac_misc_magic_wakeup,		(/* output */)		//                                    .magic_wakeup
		//.mac_mac_misc_magic_sleep_n,		(/* input */)		//                                    .magic_sleep_n
		//.mac_mac_misc_ff_tx_crc_fwd,		(/* input */)		//                                    .ff_tx_crc_fwd
		//.mac_mac_misc_ff_tx_septy,		(/* output */)		//                                    .ff_tx_septy
		//.mac_mac_misc_tx_ff_uflow,		(/* output */)		//                                    .tx_ff_uflow
		//.mac_mac_misc_ff_tx_a_full,		(/* output */)		//                                    .ff_tx_a_full
		//.mac_mac_misc_ff_tx_a_empty,		(/* output */)		//                                    .ff_tx_a_empty
		//.mac_mac_misc_rx_err_stat,		(/* output[17:0] */)	//                                    .rx_err_stat
		//.mac_mac_misc_rx_frm_type,		(/* output[3:0] */)	//                                    .rx_frm_type
		//.mac_mac_misc_ff_rx_dsav,		(/* output */)		//                                    .ff_rx_dsav
		//.mac_mac_misc_ff_rx_a_full,		(/* output */)		//                                    .ff_rx_a_full
		//.mac_mac_misc_ff_rx_a_empty,		(/* output */)		//                                    .ff_rx_a_empty
		//.mac_status_led_crs,			(/* output */)		//                      mac_status_led.crs
		//.mac_status_led_link,			(/* output */)		//                                    .link
		//.mac_status_led_col,			(/* output */)		//                                    .col
		//.mac_status_led_an,			(/* output */)		//                                    .an
		//.mac_status_led_char_err,		(/* output */)		//                                    .char_err
		//.mac_status_led_disp_err,		(/* output */)		//                                    .disp_err
		//.mac_serdes_control_export,		(/* output */)		//                  mac_serdes_control.export
		.mac_serial_txp				(lvds_txp),		//                          mac_serial.txp
		.mac_serial_rxp				(lvds_rxp),		//                                    .rxp

		// ---------------------------------------------------------------------
		// MAC (TSE) 1
		.mac1_mac_mdio_mdc			(enet1_mdc),		//                       mac1_mac_mdio.mdc
		.mac1_mac_mdio_mdio_in			(enet1_mdio_in),	//                                    .mdio_in
		.mac1_mac_mdio_mdio_out			(enet1_mdio_out),	//                                    .mdio_out
		.mac1_mac_mdio_mdio_oen			(enet1_mdio_oen),	//                                    .mdio_oen
		//.mac1_mac_misc_xon_gen,		( input )		//                       mac1_mac_misc.xon_gen
		//.mac1_mac_misc_xoff_gen,		( input )		//                                    .xoff_gen
		//.mac1_mac_misc_magic_wakeup,		( output )		//                                    .magic_wakeup
		//.mac1_mac_misc_magic_sleep_n,		( input )		//                                    .magic_sleep_n
		//.mac1_mac_misc_ff_tx_crc_fwd,		( input )		//                                    .ff_tx_crc_fwd
		//.mac1_mac_misc_ff_tx_septy,		( output )		//                                    .ff_tx_septy
		//.mac1_mac_misc_tx_ff_uflow,		( output )		//                                    .tx_ff_uflow
		//.mac1_mac_misc_ff_tx_a_full,		( output )		//                                    .ff_tx_a_full
		//.mac1_mac_misc_ff_tx_a_empty,		( output )		//                                    .ff_tx_a_empty
		//.mac1_mac_misc_rx_err_stat,		( output[17:0] )	//                                    .rx_err_stat
		//.mac1_mac_misc_rx_frm_type,		( output[3:0] )	//                                    .rx_frm_type
		//.mac1_mac_misc_ff_rx_dsav,		( output )		//                                    .ff_rx_dsav
		//.mac1_mac_misc_ff_rx_a_full,		( output )		//                                    .ff_rx_a_full
		//.mac1_mac_misc_ff_rx_a_empty,		( output )		//                                    .ff_rx_a_empty
		//.mac1_status_led_crs,			( output )		//                     mac1_status_led.crs
		//.mac1_status_led_link,		( output )		//                                    .link
		//.mac1_status_led_col,			( output )		//                                    .col
		//.mac1_status_led_an,			( output )		//                                    .an
		//.mac1_status_led_char_err,		( output )		//                                    .char_err
		//.mac1_status_led_disp_err,		( output )		//                                    .disp_err
		//.mac1_serdes_control_export,		( output )		//                 mac1_serdes_control.export
		.mac1_serial_txp			(lvds_txp1),		//                         mac1_serial.txp
		.mac1_serial_rxp			(lvds_rxp1),		//                                    .rxp

		// ---------------------------------------------------------------------/
	
		.sd_b_SD_cmd                         (SD_CMD),                         //                       sd.b_SD_cmd
		.sd_b_SD_dat                         (SD_DAT[0]),                         //                         .b_SD_dat
		.sd_b_SD_dat3                        (SD_DAT[3]),                        //                         .b_SD_dat3
		.sd_o_SD_clock                       (SD_CLK),                        //                         .o_SD_clock

		.mem_ssram_adv                 (SSRAM_ADV),                 //                fbssram_1.ssram_adv
		.mem_ssram_bwa_n               (SSRAM_BWA_n),               //                         .ssram_bwa_n
		.mem_ssram_bwb_n               (SSRAM_BWB_n),               //                         .ssram_bwb_n
		.mem_ssram_ce_n                (SSRAM_CE_n),                //                         .ssram_ce_n
		.mem_ssram_cke_n               (SSRAM_CKE_n),               //                         .ssram_cke_n
		.mem_ssram_oe_n                (SSRAM_OE_n),                //                         .ssram_oe_n
		.mem_ssram_we_n                (SSRAM_WE_n),                //                         .ssram_we_n
		.mem_fsm_a                     (FSM_A),                     //                         .fsm_a
		.mem_fsm_d_out                 (ssram_data_out),                 //                         .fsm_d_out
		.mem_fsm_d_in                  (FSM_D),                  //                         .fsm_d_in
		.mem_fsm_dout_req              (ssram_data_outen),              //                         .fsm_dout_req
		.mem_flash_adv_n               (FLASH_ADV_n),
		.mem_flash_ce_n                (FLASH_CE_n),
		.mem_flash_clk                 (FLASH_CLK),
		.mem_flash_oe_n                (FLASH_OE_n),
		.mem_flash_we_n                (FLASH_WE_n),
		.touch_x1                      (touch_x1_0),                  //                         .touch_x1
		.touch_y1                      (touch_y1_0),                  //                         .touch_y1
		.touch_x2                      (touch_x2_0),                  //                         .touch_x2
		.touch_y2                      (touch_y2_0),                  //                         .touch_y2
		.touch_count_gesture           ({touch_count_0,touch_gesture_0}),       //                         .touch_count_gesture
		.touch_touch_valid             (touch_ready_0),         //                         .touch_touch_valid
	//	.sram_clk_clk                  (sramClk),                         //                 sram_clk.clk
	//	.sram_clk_clk						 (SSRAM_CLK)
	//	.display_clk_clk					 (clk27),
		.coe_hdmi_r(HDMI_TX_RD),
		.coe_hdmi_g(HDMI_TX_GD),
		.coe_hdmi_b(HDMI_TX_BD),
		.coe_hdmi_hsd(HDMI_TX_HS),
		.coe_hdmi_vsd(HDMI_TX_VS),
		.coe_hdmi_de(HDMI_TX_DE),
		.coe_tpadlcd_mtl_r(mtl_r),
		.coe_tpadlcd_mtl_g(mtl_g),
		.coe_tpadlcd_mtl_b(mtl_b),
		.coe_tpadlcd_mtl_hsd(mtl_hsd),
		.coe_tpadlcd_mtl_vsd(mtl_vsd),
		.clk_27_clk                    (clk27),
		.coe_i2c_scl_i     				 (i2c_scl_i),
		.coe_i2c_scl_o     			    (i2c_scl_o),
		.coe_i2c_scl_oe_n  				 (i2c_scl_oe_n),
		.coe_i2c_sda_i     				 (i2c_sda_i),
		.coe_i2c_sda_o     				 (i2c_sda_o),
		.coe_i2c_sda_oe_n  				 (i2c_sda_oe_n),
		.hdmi_tx_reset_n_external_connection_export         (HDMI_TX_RST_N),
	//	.i2s_tx_conduit_end_sck        (gen_sck),                     //                  i2s_tx_conduit_end.sck
	//	.i2s_tx_conduit_end_ws         (gen_ws),                      //                                    .ws
	//	.i2s_tx_conduit_end_sd         (gen_i2s),
		.usb_coe_cs_n                               (OTG_CS_n),                               //                                 usb.coe_cs_n
		.usb_coe_rd_n                               (OTG_OE_n),                               //                                    .coe_rd_n
      .usb_coe_din                                (OTG_D),                                //                                    .coe_din
      .usb_coe_dout                               (otg_dout),                               //                                    .coe_dout
      .usb_coe_a                                  (otg_a_temp),                                  //                                    .coe_a
      .usb_coe_dc_irq_in                          (OTG_DC_IRQ),                          //                                    .coe_dc_irq_in
      .usb_coe_hc_irq_in                          (OTG_HC_IRQ),                          //                                    .coe_hc_irq_in
      //.usb_coe_dc_dreq_in                         (OTG_DC_DREQ),                         //                                    .coe_dc_dreq_in
      //.usb_coe_hc_dreq_in                         (OTG_HC_DREQ),                         //                                    .coe_hc_dreq_in
      //.usb_coe_dc_dack                            (OTG_DC_DACK),                            //                                    .coe_dc_dack
      //.usb_coe_hc_dack                            (OTG_HC_DACK),                            //                                    .coe_hc_dack
      .usb_coe_wr_n                               (OTG_WE_n),                               //                                    .coe_wr_n
      .fan_fan_on_pwm                             (FAN_CTRL),                             //
		.fan_temp_lower_seg_n                       (SEG0_D),                       //                                    .temp_lower_seg_n
		.fan_temp_upper_seg_n                       (SEG1_D),                        //                                    .temp_upper_seg_n.
		.switches_export               ({SLIDE_SW[3:0], BUTTON[3:0], SW_P[7:0]}),
		.rs232_stx_pad_o                            (UART_TXD),                            //                               rs232.stx_pad_o
		.rs232_srx_pad_i                            (UART_RXD),                            //                                    .srx_pad_i
		.rs232_rts_pad_o                            (UART_RTS),                            //                                    .rts_pad_o
		.rs232_cts_pad_i                            (UART_CTS),                            //                                    .cts_pad_i
		.rs232_dtr_pad_o                            (),                            //	.dtr_pad_o
		// I have no idea what these should be by default.  Should see Simon's example project.
		.rs232_dsr_pad_i                            (1'b1),                            //                          .dsr_pad_i
		.rs232_ri_pad_i                             (1'b1),                             //                                    .ri_pad_i
		.rs232_dcd_pad_i                            (1'b1)                            //                                    .dcd_pad_i
`ifdef	ENABLE_PCIE
		,
		.pciexpressstream_0_refclk_export           (PCIE_REFCLK_p),
		.pciexpressstream_0_fixedclk_clk            (clk125),
		.pciexpressstream_0_cal_blk_clk_clk         (reconfig_clk),
		.pciexpressstream_0_reconfig_gxbclk_clk     (reconfig_clk),
		.pciexpressstream_0_reconfig_togxb_data     (reconfig_togxb),
		.pciexpressstream_0_reconfig_fromgxb_0_data (reconfig_fromgxb),
		.pciexpressstream_0_reconfig_busy_busy_altgxb_reconfig (reconfig_busy),
		.pciexpressstream_0_pcie_rstn_export        (PCIE_PREST_n),
		.pciexpressstream_0_rx_in_rx_datain_0       (PCIE_RX_p[0]),
		.pciexpressstream_0_rx_in_rx_datain_1       (PCIE_RX_p[1]),
		.pciexpressstream_0_rx_in_rx_datain_2       (PCIE_RX_p[2]),
		.pciexpressstream_0_rx_in_rx_datain_3       (PCIE_RX_p[3]),
		.pciexpressstream_0_tx_out_tx_dataout_0     (PCIE_TX_p[0]),
		.pciexpressstream_0_tx_out_tx_dataout_1     (PCIE_TX_p[1]),
		.pciexpressstream_0_tx_out_tx_dataout_2     (PCIE_TX_p[2]),
		.pciexpressstream_0_tx_out_tx_dataout_3     (PCIE_TX_p[3])
`endif
	 );

	// handle USB (OTG) reset signal
	assign OTG_RESET_n = rstn100;

	// handle unused flash reset signal
	assign FLASH_RESET_n = rstn100;

	// handle tristate ssram data bus
	assign FSM_D         = ssram_data_outen ? ssram_data_out : 16'bzzzzzzzzzzzzzzzz;
endmodule

