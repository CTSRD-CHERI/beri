/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2014, 2015 Alexandre Joannou
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

`define AVN_JTAG_UART_BASE   35'h3f80000
`define LOOPBACK_UART_BASE   35'h3f80080
`define CHERI_NET_TX         35'h3f80100
`define CHERI_NET_RX         35'h3f80180
`define CHERI_COUNT          35'h3fc0000
`define DEBUG_JTAG_UART_BASE 35'h3f80280
`define CHERI_LEDS           35'h3f80300
`define BERI_ROM_BASE        40'h40000000
`define BERI_ROM_MASK        40'hFFFF0000
`define BLUE_BUS_BASE        40'h7F800000
`define BLUE_BUS_MASK        40'h7F800000

// Base addresses (in bytes) of peripherals, relative to BLUE_BUS_BASE
// And width of each peripheral in terms of number of bits of address space (bytes)
`define CHERI_COUNT_BASE  23'h0
`define CHERI_COUNT_WIDTH 0

`define CHERI_PIC_BASE_0 23'h4000
`ifdef MULTI
  `define CHERI_PIC_BASE_1 23'h8000
`endif
`define CHERI_PIC_WIDTH 14
