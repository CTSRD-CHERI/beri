/*-
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2011 Simon W. Moore
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
 * Description
 * 
 * Provides a set of wrappers and data structures for the PISM C simulation
 * models.
 ******************************************************************************/

package PISM;

import DefaultValue::*;

typedef enum {
  PISM_BUS_MEMORY,
  PISM_BUS_PERIPHERAL,
  PISM_BUS_TRACE
} PismBus deriving(Bits, Eq, FShow);

typedef struct {
  Bit#(64)   addr;    // 8 bytes
  Bit#(256)  data;    // 32 bytes
  Bit#(32)   byteenable;  // 4 bytes
  Bit#(8)    write; // 1 byte, 1==write, 0==read
  Bit#(152)  pad1;    // 19 bytes
} PismData deriving (Bits, Eq, Bounded);

PismData pdef = PismData {
  addr: 64'h0,
  data: 256'h0,
  byteenable: 32'hffffffff,
  write: 8'h0,
  pad1: 152'h0
};

instance DefaultValue#(PismData);
    function PismData defaultValue();
        return pdef;
    endfunction
endinstance

instance FShow#(PismData);
    function Fmt fshow(PismData pd);
        Bit#(1) onebwrite = truncate(pd.write);
        return $format("< PISMData addr: 0x%x, data: 0x%x, byte enable: 0x%x,",
            pd.addr, pd.data, pd.byteenable, "write: %b >", onebwrite);
    endfunction
endinstance

typedef enum {
    DEBUG_STREAM_0,
    DEBUG_STREAM_1
} DebugStream deriving (Bits, Eq, FShow);

// Import simple character input
import "BDPI" function ActionValue#(Bit#(32))  c_getchar();
// Import the interfaces of the PISM Bus for C peripherals
import "BDPI" function ActionValue#(Bool)      pism_init(PismBus bus);
import "BDPI" function Action                  pism_cycle_tick(PismBus bus);
import "BDPI" function Bit#(32)                pism_interrupt_get(PismBus bus);
import "BDPI" function Bool                    pism_request_ready(PismBus bus, PismData req);
import "BDPI" function Action                  pism_request_put(PismBus bus, PismData req);
import "BDPI" function Bool                    pism_response_ready(PismBus bus);
import "BDPI" function ActionValue#(Bit#(512)) pism_response_get(PismBus bus);
import "BDPI" function Bool      			   pism_addr_valid(PismBus bus, PismData req);
// Import the interfaces of a streaming character interface in C.
import "BDPI" function ActionValue#(Bool)      debug_stream_init(DebugStream ds);
import "BDPI" function Bool                    debug_stream_sink_ready(DebugStream ds);
import "BDPI" function Action                  debug_stream_sink_put(DebugStream ds, Bit#(8) char);
import "BDPI" function Bool                    debug_stream_source_ready(DebugStream ds);
import "BDPI" function ActionValue#(Bit#(8))   debug_stream_source_get(DebugStream ds);

endpackage
