/*-
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
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
 *  http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 */

import FIFO :: *;
import Vector :: *;
import RegFile :: *;
import FIFOF :: *;
import SpecialFIFOs :: *;
import DReg :: *;
import ConfigReg :: *;

interface ReadIfc#(type addr, type data);
  method Action              put(addr a);
  method ActionValue#(data)  get();
  method data                peek();
endinterface

interface MEM#(type addr, type data);
  interface ReadIfc#(addr, data) read;
  method Action write(addr a, data x);
endinterface

// Fast memory module
// This one synthesises with forwarding logic but always
// sees upldates in the next cycle.
module mkMEMfast(MEM#(addr, data))
  provisos(Bits#(addr, addr_sz),
        Bounded#(addr),
        Bits#(data, data_sz));

	RegFile#(addr,data) regFile <- mkRegFileWCF(minBound, maxBound); // BRAM
	FIFO#(addr)         readReq <- mkSizedFIFO(4);

	interface ReadIfc read;
   method Action put(addr a) = readReq.enq(a);
   method data peek() = regFile.sub(readReq.first());
   method ActionValue#(data) get();
    readReq.deq();
    return regFile.sub(readReq.first());
   endmethod
  endinterface
  method Action write(addr a, data x) = regFile.upd(a,x);
endmodule

// Efficient memory module.  This one synthesises to a single
// BRAM with no forwarding logic, but deleays reads to locations
// that are written in the same cycle.
module mkMEMsmall(MEM#(addr, data))
  provisos(Bits#(addr, addr_sz),
        Bounded#(addr),
        Bits#(data, data_sz),
        Eq#(addr));

	RegFile#(addr,data) regFile <- mkRegFileWCF(minBound, maxBound); // BRAM
	FIFOF#(addr)        readReq <- mkSizedBypassFIFOF(4);
	FIFO#(Bit#(0))      outReady <- mkLFIFO;
	Reg#(data)            outReg <- mkConfigRegU;
	Reg#(addr)       readAddr[2] <- mkCReg(2,?);
	Reg#(Maybe#(addr)) writeAddr <- mkDReg(tagged Invalid);

	rule doRead;
	  readAddr[0] <= readReq.first();
	  readReq.deq();
	  outReady.enq(?);
	endrule
	rule updateRead;
	  outReg <= regFile.sub(readAddr[1]);
	endrule
 
	Bool readReady = !isValid(writeAddr) || (readAddr[0] != fromMaybe(?,writeAddr));

	interface ReadIfc read;
   method Action put(addr a) = readReq.enq(a);
   method data peek() if (readReady) = outReg;
   method ActionValue#(data) get() if (readReady);
     outReady.deq;
     return outReg;
   endmethod
  endinterface
  method Action write(addr a, data d);
    regFile.upd(a,d);
    writeAddr <= tagged Valid a;
  endmethod
endmodule

module mkMEM(MEM#(addr, data))
  provisos(Bits#(addr, addr_sz),
        Bounded#(addr),
        Bits#(data, data_sz),
        Eq#(addr));
  MEM#(addr,data) ifc <- mkMEMfast;
  return ifc;
endmodule

// Unguarded memory module
// This one keeps the address in a register with no
// flow control.
module mkMEMNoFlow(MEM#(addr, data))
  provisos(Bits#(addr, addr_sz),
        Bounded#(addr),
        Eq#(addr),
        Bits#(data, data_sz));
  
  MEM#(addr, data) bram <- mkMEMCore();
  Reg#(addr)  writeAddr <- mkConfigRegU;
  Reg#(data)  writeData <- mkConfigRegU;
  Reg#(addr)   readAddr <- mkConfigRegU;

	interface ReadIfc read;
    method Action put(addr a);
      readAddr <= a;
      bram.read.put(a);
    endmethod
    method data peek();
      return (readAddr == writeAddr) ? writeData:bram.read.peek();
    endmethod
    method ActionValue#(data) get();
      return (readAddr == writeAddr) ? writeData:bram.read.peek();
    endmethod
  endinterface
  method Action write(addr a, data x);
    writeAddr <= a;
    writeData <= x;
    bram.write(a,x);
  endmethod
endmodule

module mkMEMNoFlowSlow(MEM#(addr, data))
  provisos(Bits#(addr, addr_sz),
        Bounded#(addr),
        Eq#(addr),
        Bits#(data, data_sz));

	RegFile#(addr,data)  regFile <- mkRegFileWCF(minBound, maxBound); // BRAM
	Reg#(data)          readData <- mkRegU;
	Reg#(addr)       readAddr[2] <- mkCReg(2,?);
	Reg#(addr)         writeAddr <- mkWire;
	Reg#(Bool)     readDataValid <- mkDReg(True);

	rule updateRead;
	  readData <= regFile.sub(readAddr[1]);
	endrule
	
	rule updateGuard;
	  if (writeAddr == readAddr[1]) readDataValid <= False;
	endrule
	
	interface ReadIfc read;
   method Action put(addr a) = readAddr[0]._write(a);
   method data peek() if (readDataValid) = readData;
   method ActionValue#(data) get() if (readDataValid);
     return readData;
   endmethod
  endinterface
  method Action write(addr a, data x);
    writeAddr <= a;
    regFile.upd(a,x);
  endmethod
endmodule


typedef Bit#(8) Byte;

interface MemBEVerbose#(type addr, type data, numeric type data_bytes);
  interface ReadIfc#(addr, data) read;
  method Action write(addr a, data x, Vector#(data_bytes,Bool) be);
endinterface

typedef MemBEVerbose#(addr,data,TDiv#(SizeOf#(data),8)) MemBE#(type addr, type data);

function data fromChunks(Vector#(n,chunk) vec)
provisos(
  Bits#(data,data_sz),
  Bits#(chunk,chunk_sz),
  Mul#(chunk_sz,n,data_sz)
);
  return unpack(truncate(pack(vec)));
endfunction

module mkMemBE(MemBE#(addr, data))
provisos(
  Bits#(addr, addr_sz),
  Bounded#(addr),
  Bits#(data, data_sz),
  Mul#(data_bytes, 8, data_sz),
  Div#(data_sz, 8, data_bytes)
);

  Vector#(data_bytes,RegFile#(addr,Byte))
   regFiles <- replicateM(mkRegFileWCF(minBound, maxBound));
  FIFO#(addr) readReq <- mkSizedFIFO(4);

  function readF(rf) = rf.sub(readReq.first);
  Vector#(data_bytes,Byte) readBytes = map(readF,regFiles);
  data readResult = fromChunks(readBytes);


  method Action write(addr a, data x, Vector#(data_bytes,Bool) be);
   Vector#(data_bytes,Byte) bytes = unpack(pack(x));
   function writeF(rf, b, en) = action
    if (en) begin
      rf.upd(a,b);
    end
   endaction;
   let _ <- zipWith3M(writeF,regFiles,bytes,be);
  endmethod

  interface ReadIfc read;
   method Action put(addr a) = readReq.enq(a);
   method ActionValue#(data) get();
    readReq.deq();
    return readResult;
   endmethod
   method data peek = readResult;
  endinterface
endmodule

// 2 read interface version of memory (should use 2x BRAMs in synthesis)

interface MEM2#(type addr, type data);
  interface ReadIfc#(addr, data) read;
  interface ReadIfc#(addr, data) readB;
  method Action write(addr a, data x);
endinterface

// Unguarded memory module
// This one keeps the address in a register with no
// flow control.
module mkMEMNoFlow2(MEM2#(addr, data))
  provisos(Bits#(addr, addr_sz),
        Bounded#(addr),
        Eq#(addr),
        Bits#(data, data_sz));
  
  MEM#(addr, data) bramA  <- mkMEMCore();
  MEM#(addr, data) bramB  <- mkMEMCore();
  Reg#(addr)  writeAddr  <- mkConfigRegU;
  Reg#(data)  writeData  <- mkConfigRegU;
  Reg#(addr)   readAddr  <- mkConfigRegU;
  Reg#(addr)   readAddrB <- mkConfigRegU;

  interface ReadIfc read;
    method Action put(addr a);
      readAddr <= a;
      bramA.read.put(a);
    endmethod
    method data peek();
      return (readAddr == writeAddr) ? writeData:bramA.read.peek();
    endmethod
    method ActionValue#(data) get();
      return (readAddr == writeAddr) ? writeData:bramA.read.peek();
    endmethod
  endinterface
  interface ReadIfc readB;
    method Action put(addr a);
      readAddrB <= a;
      bramB.read.put(a);
    endmethod
    method data peek();
      return (readAddrB == writeAddr) ? writeData:bramB.read.peek();
    endmethod
    method ActionValue#(data) get();
      return (readAddrB == writeAddr) ? writeData:bramB.read.peek();
    endmethod
  endinterface
  method Action write(addr a, data x);
    writeAddr <= a;
    writeData <= x;
    bramA.write(a,x);
    bramB.write(a,x);
  endmethod
endmodule

// Version of BRAM using explicit Altera Block RAM verilog.
// This greatly accelerates synthesis for big memories.

import "BVI" AltMEM =
module vAltMEMCore(MEM#(addr, data))
  provisos(
     Bits#(addr, addr_sz),
     Bits#(data, data_sz)
     );

  parameter ADDR_WIDTH = valueof(addr_sz);
  parameter DATA_WIDTH = valueof(data_sz);
  parameter MEMSIZE    = Bit#(TAdd#(1,addr_sz)) ' (fromInteger(valueOf(TExp#(addr_sz))));

  interface ReadIfc read;
    method put((* reg *)ADDRR) enable(REN);
    method DO peek();
    method DO get() enable(EN_UNUSED2);
  endinterface: read
  
  method write((* reg *)ADDRW, (* reg *)DI) enable(WEN);

  schedule (read_put) CF (read_peek, read_get);
  schedule read_peek CF read_peek;
  schedule (write) CF (read_put, read_peek, read_get);
  schedule read_peek CF read_get;
  schedule read_get CF read_get;
  schedule write C write;
  schedule read_put C read_put;
endmodule: vAltMEMCore

module mkMEMCoreBSC(MEM#(addr, data))
  provisos(Bits#(addr, addr_sz),
        Bounded#(addr),
        Bits#(data, data_sz));
  
  RegFile#(addr,data)  regFile <- mkRegFileWCF(minBound, maxBound); // BRAM
  Reg#(addr)          readAddr <- mkRegU;
  Reg#(addr)         writeAddr <- mkRegU;
  Reg#(data)         writeData <- mkRegU;
  
  rule doDataWrite;
    regFile.upd(writeAddr, writeData);
  endrule
  
  interface ReadIfc read;
   method Action put(addr a) = readAddr._write(a);
   method data peek() = regFile.sub(readAddr);
   method ActionValue#(data) get();
     return regFile.sub(readAddr);
   endmethod
  endinterface
  method Action write(addr a, data x);
    writeAddr <= a;
    writeData <= x;
  endmethod
endmodule: mkMEMCoreBSC


//////////////////////////////////////////////
// Wrapper for the verilog and bluespec implementations.
/////////////////////////////////////////////

module mkMEMCore(MEM#(addr, data))
   provisos(
      Bits#(addr, addr_sz),
      Bits#(data, data_sz),
      Bounded#(addr)
      );

   Clock clk <- exposeCurrentClock;
   Reset rst <- exposeCurrentReset;
   (*hide*)
  `ifndef BLUESIM
    let _ifc <- vAltMEMCore();
  `else
    let _ifc <- mkMEMCoreBSC;
  `endif
   return _ifc ;
endmodule
