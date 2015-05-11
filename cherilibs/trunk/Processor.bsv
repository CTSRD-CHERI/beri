/*-
 * Copyright (c) 2011-2013 SRI International
 * Copyright (c) 2013 Philip Withnall
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2014 Alexandre Joannou
 * Copyright (c) 2015 Paul J. Fox
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
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
 ******************************************************************************
 *
 * Author: Nirav Dave <ndave@csl.sri.com>
 *
 ******************************************************************************
 *
 * Description: Top-Level Cheri Processor Interface
 *
 ******************************************************************************/

import ClientServer::*;
import Vector::*;
import TLM3::*;

import MasterSlave::*;
import PIC::*;
import Peripheral::*;
import MemTypes::*;

`ifdef RMA
import AvalonStreaming::*;
`endif

`ifdef DMA_VIRT
    import MIPS::*;
`endif

interface Processor;
  method Action putIrqs(Bit#(32) interruptLines);
  interface Master#(CheriMemRequest, CheriMemResponse) extMemory;
  interface Vector#(CORE_COUNT, Server#(Bit#(8), Bit#(8))) debugStream;
  interface Vector#(CORE_COUNT, Peripheral#(0)) pic;
  method Bool reset_n();

  `ifdef CP1X
  method Action cp1xdIn(Value v);
  method ActionValue#(Value) cp1xdOut;
  `endif

  `ifdef RMA
  interface AvalonStreamSourcePhysicalIfc#(Bit#(76)) networkRx;
  interface AvalonStreamSinkPhysicalIfc#(Bit#(76)) networkTx;
  `endif

  `ifdef DMA_VIRT
  interface Vector#(2, Server#(TlbRequest, TlbResponse)) tlbs;
  `endif
endinterface
