#
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2013 Bjoern A. Zeeb
# Copyright (c) 2014 A. Theodore Markettos
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


# Triple-speed Ethernet timing constraints file

# Path to the TSE
set SYSTEM_PATH_PREFIX ""

# Network-side interface clocks/reference clocks
set TSE_CLOCK_FREQUENCY "125 MHz"

# FIFO data interface clock 
set FIFO_CLOCK_FREQUENCY "50 MHz"

# Control/status interface clock
set DEFAULT_SYSTEM_CLOCK_SPEED "50 MHz"

# Phase measure clock
set PHASE_MEASURE_CLOCK_SPEED "50 MHz"

# Clocks coming into the TSE core and their names in the hierarchy
set  TX_CLK             "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|tx_clk"
set  RX_CLK             "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|rx_clk"
set  CLK                "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|clk"
set  FF_TX_CLK          "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|ff_tx_clk"
set  FF_RX_CLK          "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|ff_rx_clk"
set  TBI_TX_CLK         "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|tbi_tx_clk"
set  TBI_RX_CLK         "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|tbi_rx_clk"
set  REF_CLK            "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|ref_clk"
set  PCS_PHASE_MEASURE_CLK "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac|pcs_phase_measure_clk"

set  TX_CLK1		"|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|tx_clk"
set  RX_CLK1		"|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|rx_clk"
set  CLK1		"|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|clk"
set  FF_TX_CLK1		"|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|ff_tx_clk"
set  FF_RX_CLK1		"|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|ff_rx_clk"
set  TBI_TX_CLK1	"|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|tbi_tx_clk"
set  TBI_RX_CLK1	"|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|tbi_rx_clk"
set  REF_CLK1		"|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|ref_clk"
set  PCS_PHASE_MEASURE_CLK1 "|DE4_BERI|DE4_SOC:DE4_SOC_inst|DE4_SOC_tse_mac:tse_mac1|pcs_phase_measure_clk"
