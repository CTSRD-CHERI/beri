/* Copyright 2015 Matthew Naylor
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
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream
 * Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
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
import MemTypes     :: *;

// ======================================
// Connect to hash table implemented in C
// ======================================

// Allocate hash table of given size where keySize and valSize denote
// the number of 32-bit words in the key and value.
import "BDPI" function Action hashInit(
  Bit#(32) numEntries, Bit#(32) keySize, Bit#(32) valSize);

// Insert into hash table
import "BDPI" function Action hashInsert(CheriPhyLineNumber addr, Bit#(CheriDataWidth) data);

// Lookup in hash table
import "BDPI" function Bit#(CheriDataWidth) hashLookup(Bit#(CheriLineAddrWidth) addr);

// =====================
// Module implementation
// =====================

module mkRegFileHash#(Bit#(32) numEntries) (RegFile#(CheriPhyLineNumber, Bit#(CheriDataWidth)));

  Reg#(Bool) init <- mkReg(True);

  rule initialise (init);
    hashInit(numEntries, 2, 8); // Upper bound, 2*32bits address, 8*32bits data
    init <= False;
  endrule

  method Action upd(CheriPhyLineNumber addr, Bit#(CheriDataWidth) data) if (!init);
    hashInsert(addr, zeroExtend(data));
  endmethod

  method Bit#(CheriDataWidth) sub(CheriPhyLineNumber addr) if (!init);
    return truncate(hashLookup(addr));
  endmethod

endmodule
