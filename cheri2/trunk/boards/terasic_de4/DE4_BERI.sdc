#
# Copyright (c) 2012-2013 Jonathan Woodruff
# Copyright (c) 2014 A. Theodore Markettos
# Copyright (c) 2013 Robert M. Norton
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for
# additional information regarding copyright ownership.  BERI licenses this
# file to you under the BERI Hardware-Software License, Version 1.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at:
#
#   http://www.beri-open-systems.org/legal/license-1-0.txt
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
# @BERI_LICENSE_HEADER_END@
#


# clocks
create_clock -add -name "CLK_50_ETH_pll" -period "50 MHZ" [get_ports OSC_50_Bank2]
create_clock -add -name "CLK_50_MAIN_pll" -period "50 MHZ" [get_ports OSC_50_Bank3]
create_clock -add -name "CLK_50" -period "50 MHZ" [get_ports OSC_50_Bank4]
create_clock -add -name "CLK_100_PCIE_REFCLK" -period "100 MHZ" [get_ports PCIE_REFCLK_p]
#create_clock -period 20 -waveform {0 10} OSC_50_Bank4

# generate clocks
derive_pll_clocks

# clock uncertainty
derive_clock_uncertainty

# Clock constraints
# ports constrained by CLK_50 from the external pll
set_input_delay -clock "CLK_50" -max 0ns [get_ports {GPIO0_D[*]}] -add_delay
set_input_delay -clock "CLK_50" -min 0ns [get_ports {GPIO0_D[*]}] -add_delay
set_input_delay -clock "CLK_50" -max 0ns [get_ports {UART_CTS UART_RXD}] -add_delay
set_input_delay -clock "CLK_50" -min 0ns [get_ports {UART_CTS UART_RXD}] -add_delay
set_output_delay -clock "CLK_50" -max 0ns [get_ports {UART_RTS UART_TXD}] -add_delay
set_output_delay -clock "CLK_50" -min 0ns [get_ports {UART_RTS UART_TXD}] -add_delay

# sd clock and the outputs related to it
create_clock -period 20.000ns [get_ports {SD_CLK}]
set_input_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -max 0ns [get_ports {SD_CMD SD_DAT[*]}] -add_delay
set_input_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -min 0ns [get_ports {SD_CMD SD_DAT[*]}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -max 0ns [get_ports {SD_CLK SD_CMD SD_DAT[*]}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -min 0ns [get_ports {SD_CLK SD_CMD SD_DAT[*]}] -add_delay

# display clock and the outputs related to it
#create_clock -period "27.0 MHZ" [get_ports mtl_dclk]
set_output_delay -clock "display_pll_ins|altpll_component|auto_generated|pll1|clk[0]" -max 5ns [get_ports {mtl_dclk mtl_*[*] mtl_hsd mtl_vsd}] -add_delay
set_output_delay -clock "display_pll_ins|altpll_component|auto_generated|pll1|clk[0]" -min -5ns [get_ports {mtl_dclk mtl_*[*] mtl_hsd mtl_vsd}] -add_delay
#set_output_delay -clock "display_pll_ins|altpll_component|auto_generated|pll1|clk[0]" -max 0ns [get_ports {DE4_SOC:DE4_SOC_inst|DE4_SOC_peripherals_0:peripherals_0|mkAvalonStream2LCDandHDMI:avalonstream2lcdandhdmi_0|asi_stream_in_endofpacket~QIC_DANGLING_PORT}] -add_delay
#set_output_delay -clock "display_pll_ins|altpll_component|auto_generated|pll1|clk[0]" -min 0ns [get_ports {DE4_SOC:DE4_SOC_inst|DE4_SOC_peripherals_0:peripherals_0|mkAvalonStream2LCDandHDMI:avalonstream2lcdandhdmi_0|asi_stream_in_endofpacket~QIC_DANGLING_PORT}] -add_delay
#create_clock -period "27.0 MHZ" [get_ports HDMI_TX_PCLK]
set_input_delay -clock "CLK_50" -max 0ns [get_ports HDMI_TX_PCS*] -add_delay
set_input_delay -clock "CLK_50" -min 0ns [get_ports HDMI_TX_PCS*] -add_delay
set_output_delay -clock "CLK_50" -max 0ns [get_ports {HDMI_TX_*D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_PCLK HDMI_TX_RST_N HDMI_TX_VS}] -add_delay
set_output_delay -clock "CLK_50" -min 0ns [get_ports {HDMI_TX_*D[*] HDMI_TX_DE HDMI_TX_HS HDMI_TX_PCLK HDMI_TX_RST_N HDMI_TX_VS}] -add_delay

# i2c clock for the touch controller and outputs related to it
create_generated_clock -source OSC_50_Bank4 i2c_touch_config:touch|step_i2c_clk
create_generated_clock -source OSC_50_Bank4 i2c_touch_config:touch|step_i2c_clk_out
#create_clock -period "80.0 KHZ" [get_ports mtl_touch_i2cscl]
set_input_delay -clock "i2c_touch_config:touch|step_i2c_clk_out" -max 0ns [get_ports {mtl_touch_i2csda}] -add_delay
set_input_delay -clock "i2c_touch_config:touch|step_i2c_clk_out" -min 0ns [get_ports {mtl_touch_i2csda}] -add_delay
set_output_delay -clock "i2c_touch_config:touch|step_i2c_clk_out" -max 0ns [get_ports {mtl_touch_i2cscl mtl_touch_i2csda}] -add_delay
set_output_delay -clock "i2c_touch_config:touch|step_i2c_clk_out" -min 0ns [get_ports {mtl_touch_i2cscl mtl_touch_i2csda}] -add_delay

# Altera suggest specifying the clock but this often seems to be already specified:
#   create_clock     -name { tck } -period "100MHz" [get_ports altera_reserved_tck]
# Altera suggest making the clock "exclusive" but I believe that it should be "asynchronous"
# with respect to the other clocks (see the clock grouping section)
#   set_clock_groups -exclusive -group [get_clocks tck]
set_input_delay  -clock { altera_reserved_tck } -max 0ns [get_ports altera_reserved_tdi] -add_delay
set_input_delay  -clock { altera_reserved_tck } -min 0ns [get_ports altera_reserved_tdi] -add_delay
set_input_delay  -clock { altera_reserved_tck } -max 0ns [get_ports altera_reserved_tms] -add_delay
set_input_delay  -clock { altera_reserved_tck } -min 0ns [get_ports altera_reserved_tms] -add_delay
set_output_delay -clock { altera_reserved_tck } -max 0ns [get_ports altera_reserved_tdo] -add_delay
set_output_delay -clock { altera_reserved_tck } -min 0ns [get_ports altera_reserved_tdo] -add_delay

# create virtual clock (1MHz) for input key presses and make asynchronous with master clock and associate with buttons
create_clock -period "1MHz" -name human_clk
set_input_delay -clock { human_clk } -add_delay 0 [get_ports {BUTTON[*]}]
set_input_delay -clock { human_clk } -add_delay 0 [get_ports CPU_RESET_n]
set_input_delay -clock { human_clk } -add_delay 0 [get_ports SW[*]]
set_input_delay -clock { human_clk } -add_delay 0 [get_ports SLIDE_SW[*]]
set_input_delay -clock { human_clk } -add_delay 0 [get_ports mtl_touch_int]
# These are driven by other clocks but have no output timing requirements.
set_output_delay -clock { human_clk } -max 0ns [get_ports LED[*]] -add_delay
set_output_delay -clock { human_clk } -min 0ns [get_ports LED[*]] -add_delay
set_output_delay -clock { human_clk } -max 0ns [get_ports {SEG*_D[*] FAN_CTRL}] -add_delay
set_output_delay -clock { human_clk } -min 0ns [get_ports {SEG*_D[*] FAN_CTRL}] -add_delay

# constrain input and output ports on the ethernet clock
create_generated_clock -source OSC_50_Bank4 DE4_SOC:DE4_SOC_inst|DE4_SOC_peripherals_0:peripherals_0|DE4_SOC_peripherals_0_tse_mac:tse_mac1|altera_tse_mac_pcs_pma:altera_tse_mac_pcs_pma_inst|altera_tse_mac_pcs_pma_ena:altera_tse_mac_pcs_pma_ena_inst|altera_tse_top_gen_host:top_gen_host_inst|altera_tse_top_mdio:U_MDIO|altera_tse_mdio_clk_gen:U_CLKGEN|mdio_clk
create_generated_clock -source OSC_50_Bank4 DE4_SOC:DE4_SOC_inst|DE4_SOC_peripherals_0:peripherals_0|DE4_SOC_peripherals_0_tse_mac:tse_mac|altera_tse_mac_pcs_pma:altera_tse_mac_pcs_pma_inst|altera_tse_mac_pcs_pma_ena:altera_tse_mac_pcs_pma_ena_inst|altera_tse_top_gen_host:top_gen_host_inst|altera_tse_top_mdio:U_MDIO|altera_tse_mdio_clk_gen:U_CLKGEN|mdio_clk
create_generated_clock -source DE4_SOC:DE4_SOC_inst|DE4_SOC_peripherals_0:peripherals_0|DE4_SOC_peripherals_0_tse_mac:tse_mac|altera_tse_mac_pcs_pma:altera_tse_mac_pcs_pma_inst|altera_tse_mac_pcs_pma_ena:altera_tse_mac_pcs_pma_ena_inst|altera_tse_top_gen_host:top_gen_host_inst|altera_tse_top_mdio:U_MDIO|altera_tse_mdio_clk_gen:U_CLKGEN|mdio_clk ETH_MDC[0]
create_generated_clock -source DE4_SOC:DE4_SOC_inst|DE4_SOC_peripherals_0:peripherals_0|DE4_SOC_peripherals_0_tse_mac:tse_mac1|altera_tse_mac_pcs_pma:altera_tse_mac_pcs_pma_inst|altera_tse_mac_pcs_pma_ena:altera_tse_mac_pcs_pma_ena_inst|altera_tse_top_gen_host:top_gen_host_inst|altera_tse_top_mdio:U_MDIO|altera_tse_mdio_clk_gen:U_CLKGEN|mdio_clk ETH_MDC[1]
set_input_delay -clock { CLK_50 } -max 0ns [get_ports ETH_MDIO[*]] -add_delay
set_input_delay -clock { CLK_50 } -min 0ns [get_ports ETH_MDIO[*]] -add_delay
set_output_delay -clock { CLK_50 } -max 0ns [get_ports {ETH_MDIO[*] ETH_MDC[*] ETH_RST_n}] -add_delay
set_output_delay -clock { CLK_50 } -min 0ns [get_ports {ETH_MDIO[*] ETH_MDC[*] ETH_RST_n}] -add_delay

# constrain input and output ports on the 100MHz system clock
create_generated_clock -source DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] SSRAM_CLK
set_output_delay -clock {SSRAM_CLK} -max 0ns [get_ports {SSRAM_CLK}] -add_delay
set_output_delay -clock {SSRAM_CLK} -min 0ns [get_ports {SSRAM_CLK}] -add_delay
set_output_delay -clock {SSRAM_CLK} -max -5ns [get_ports {FSM_D[*] FSM_A[*] SSRAM_ADV SSRAM_BWA_n SSRAM_BWB_n SSRAM_CE_n SSRAM_CKE_n SSRAM_OE_n SSRAM_WE_n}] -add_delay
set_output_delay -clock {SSRAM_CLK} -min 5ns [get_ports {FSM_D[*] FSM_A[*] SSRAM_ADV SSRAM_BWA_n SSRAM_BWB_n SSRAM_CE_n SSRAM_CKE_n SSRAM_OE_n SSRAM_WE_n}] -add_delay

set_input_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -max 0ns [get_ports FSM_D[*]] -add_delay
set_input_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -min 0ns [get_ports FSM_D[*]] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -max 0ns [get_ports {FLASH_ADV_n FLASH_CE_n FLASH_OE_n FLASH_RESET_n FLASH_WE_n}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -min 0ns [get_ports {FLASH_ADV_n FLASH_CE_n FLASH_OE_n FLASH_RESET_n FLASH_WE_n}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -max 0ns [get_ports {HDMI_TX_PCSCL HDMI_TX_PCSDA}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -min 0ns [get_ports {HDMI_TX_PCSCL HDMI_TX_PCSDA}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -max -5ns [get_ports {FLASH_CLK}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -min 5ns [get_ports {FLASH_CLK}] -add_delay
set_input_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -max 0ns [get_ports {OTG_D[*] OTG_DC_IRQ OTG_HC_IRQ}] -add_delay
set_input_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -min 0ns [get_ports {OTG_D[*] OTG_DC_IRQ OTG_HC_IRQ}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -max 0ns [get_ports {OTG_D[*] OTG_A[*] OTG_CS_n OTG_OE_n OTG_RESET_n OTG_WE_n}] -add_delay
set_output_delay -clock { DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] } -min 0ns [get_ports {OTG_D[*] OTG_A[*] OTG_CS_n OTG_OE_n OTG_RESET_n OTG_WE_n}] -add_delay

# specify which clocks are asynchronous with respect to each other
set_clock_groups -asynchronous \
					  -group { CLK_50_ETH_pll \
								  DE4_SOC:DE4_SOC_inst|DE4_SOC_peripherals_0:peripherals_0|DE4_SOC_peripherals_0_tse_mac:tse_mac1|altera_tse_mac_pcs_pma:altera_tse_mac_pcs_pma_inst|altera_tse_mac_pcs_pma_ena:altera_tse_mac_pcs_pma_ena_inst|altera_tse_top_gen_host:top_gen_host_inst|altera_tse_top_mdio:U_MDIO|altera_tse_mdio_clk_gen:U_CLKGEN|mdio_clk \
								  DE4_SOC:DE4_SOC_inst|DE4_SOC_peripherals_0:peripherals_0|DE4_SOC_peripherals_0_tse_mac:tse_mac|altera_tse_mac_pcs_pma:altera_tse_mac_pcs_pma_inst|altera_tse_mac_pcs_pma_ena:altera_tse_mac_pcs_pma_ena_inst|altera_tse_top_gen_host:top_gen_host_inst|altera_tse_top_mdio:U_MDIO|altera_tse_mdio_clk_gen:U_CLKGEN|mdio_clk \
								  DE4_SOC_inst|peripherals_0|tse_mac1|altera_tse_mac_pcs_pma_inst|the_altera_tse_pma_lvds_rx|ALTLVDS_RX_component|auto_generated|rx[0]|clk0 \
								  DE4_SOC_inst|peripherals_0|tse_mac|altera_tse_mac_pcs_pma_inst|the_altera_tse_pma_lvds_rx|ALTLVDS_RX_component|auto_generated|rx[0]|clk0 \
								  pll_125_ins|altpll_component|auto_generated|pll1|clk[0] \
								} \
					  -group { display_pll_ins|altpll_component|auto_generated|pll1|clk[0] \
								} \
					  -group { CLK_50 \
						        CLK_50_MAIN_pll \
								  SD_CLK \
								  DE4_SOC_inst|ddr2|DE4_SOC_ddr2_p0_leveling_clk \
								  DE4_SOC_inst|ddr2|div_clock_0 \
								  DE4_SOC_inst|ddr2|div_clock_1 \
								  DE4_SOC_inst|ddr2|div_clock_2 \
								  DE4_SOC_inst|ddr2|div_clock_3 \
								  DE4_SOC_inst|ddr2|div_clock_4 \
								  DE4_SOC_inst|ddr2|div_clock_5 \
								  DE4_SOC_inst|ddr2|div_clock_6 \
								  DE4_SOC_inst|ddr2|div_clock_7 \
								  DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] \
								  DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[1] \
								  DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[2] \
								  DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[3] \
								  DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[5] \
								  DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[6] \
								  M1_DDR2_clk[0] \
								  M1_DDR2_clk[1] \
								  M1_DDR2_clk_n[0] \
								  M1_DDR2_clk_n[1] \
								  M1_DDR2_dqs[0]_IN \
								  M1_DDR2_dqs[0]_OUT \
								  M1_DDR2_dqs[1]_IN \
								  M1_DDR2_dqs[1]_OUT \
								  M1_DDR2_dqs[2]_IN \
								  M1_DDR2_dqs[2]_OUT \
								  M1_DDR2_dqs[3]_IN \
								  M1_DDR2_dqs[3]_OUT \
								  M1_DDR2_dqs[4]_IN \
								  M1_DDR2_dqs[4]_OUT \
								  M1_DDR2_dqs[5]_IN \
								  M1_DDR2_dqs[5]_OUT \
								  M1_DDR2_dqs[6]_IN \
								  M1_DDR2_dqs[6]_OUT \
								  M1_DDR2_dqs[7]_IN \
								  M1_DDR2_dqs[7]_OUT \
								  M1_DDR2_dqsn[0]_OUT \
								  M1_DDR2_dqsn[1]_OUT \
								  M1_DDR2_dqsn[2]_OUT \
								  M1_DDR2_dqsn[3]_OUT \
								  M1_DDR2_dqsn[4]_OUT \
								  M1_DDR2_dqsn[5]_OUT \
								  M1_DDR2_dqsn[6]_OUT \
								  M1_DDR2_dqsn[7]_OUT \
								  DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0] \
								} \
					  -group { SSRAM_CLK } \
					  -group { i2c_touch_config:touch|step_i2c_clk_out } \
					  -group { i2c_touch_config:touch|step_i2c_clk } \
					  -group { CLK_100_PCIE_REFCLK } \
                 -group { altera_reserved_tck } \
                 -group { human_clk }

