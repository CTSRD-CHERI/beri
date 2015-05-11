/*-
 * Copyright (c) 2015 Matthew Naylor
 * All rights reserved.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
 * project, funded by EPSRC grant EP/K008528/1.
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

import RegFile :: *;

// ======================================
// Connect to hash table implemented in C
// ======================================

// Allocate hash table of given size where keySize and valSize denote
// the number of 32-bit words in the key and value.
import "BDPI" function Action hashInit(
  Bit#(32) numEntries, Bit#(32) keySize, Bit#(32) valSize);

// Insert into hash table
import "BDPI" function Action hashInsert(Bit#(35) addr, Bit#(256) data);

// Lookup in hash table
import "BDPI" function Bit#(256) hashLookup(Bit#(35) addr);

// =====================
// Module implementation
// =====================

module mkRegFileHash#(Bit#(32) numEntries) (RegFile#(Bit#(35), Bit#(256)));

  Reg#(Bool) init <- mkReg(True);

  rule initialise (init);
    hashInit(numEntries, 2, 8);
    init <= False;
  endrule

  method Action upd(Bit#(35) addr, Bit#(256) data) if (!init);
    hashInsert(addr, data);
  endmethod

  method Bit#(256) sub(Bit#(35) addr) if (!init);
    return hashLookup(addr);
  endmethod

endmodule
