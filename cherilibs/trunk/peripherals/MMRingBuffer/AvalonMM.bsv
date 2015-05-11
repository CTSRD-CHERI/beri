/*-
 * Copyright (c) 2013 Alex Horsman
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

package AvalonMM;

import GetPut::*;
import ClientServer::*;
import FIFO::*;
import FIFOF::*;
import FIFOLevel::*;


typedef union tagged {
  struct {
    addressT address;
    Bit#(TMul#(byteEnable,TDiv#(SizeOf#(dataT),8))) byteenable;
    UInt#(burstWidth) burstcount;
  } AvalonRead;
  struct {
    dataT writedata;
    addressT address;
    Bit#(TMul#(byteEnable,TDiv#(SizeOf#(dataT),8))) byteenable;
    UInt#(burstWidth) burstcount;
  } AvalonWrite;
} AvalonMMRequest#(
  type dataT,
  type addressT,
  numeric type burstWidth,
  numeric type byteEnable
) deriving(Bits);

typedef dataT AvalonMMResponse#(type dataT);


//External interface for an Avalon Master device.
(* always_ready, always_enabled *)
interface AvalonMasterExtVerbose#(
  type dataT,
  type addressT,
  numeric type burstWidth,
  numeric type byteEnableWidth
);
  method Action avm(
    dataT readdata,
    Bool readdatavalid,
    Bool waitrequest
  );
  method dataT avm_writedata;
  method addressT avm_address;
  method Bool avm_read;
  method Bool avm_write;
  method Bit#(byteEnableWidth) avm_byteenable;
  method UInt#(burstWidth) avm_burstcount;
endinterface

typedef AvalonMasterExtVerbose#(dataT,addressT,burstWidth,TMul#(byteEnable,TDiv#(SizeOf#(dataT),8)))
  AvalonMasterExt#(type dataT,type addressT,numeric type burstWidth,numeric type byteEnable);


//Internal interface to expose the phases of the
//Avalon Master protocol as Action methods.
interface AvalonMaster#(
  type dataT,
  type addressT,
  numeric type burstWidth,
  numeric type byteEnable
);
  interface AvalonMasterExt#(dataT,addressT,burstWidth,byteEnable) avm;
  interface Server#(
    AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable),
    AvalonMMResponse#(dataT)
  ) server;
endinterface

module mkAvalonMaster(AvalonMaster#(dataT,addressT,burstWidth,byteEnable))
provisos(
  Bits#(dataT,dataWidth),
  Bits#(addressT,addressWidth),
  Mul#(8,dataBytes,dataWidth)
);

  RWire#(AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable))
    req <- mkRWire;

  Wire#(Bool) reqReady <- mkWire;

  //Should be UGBypassFIFO
  FIFOF#(dataT) resp <- mkGLFIFOF(True,False);

  //External interface wiring
  interface AvalonMasterExtVerbose avm;
    method Action avm(readdata,readdatavalid,waitrequest);
      if (readdatavalid) begin
        resp.enq(readdata);
      end
      reqReady <= !waitrequest;
    endmethod
    method avm_writedata = case (fromMaybe(?,req.wget)) matches
      tagged AvalonWrite { writedata: .w } : return w;
    endcase;
    method avm_address = case (fromMaybe(?,req.wget)) matches
      tagged AvalonRead  { address: .a } : return a;
      tagged AvalonWrite { address: .a } : return a;
    endcase;
    method avm_read = case (req.wget) matches
      tagged Valid (tagged AvalonRead {}) : return True;
      default : return False;
    endcase;
    method avm_write = case (req.wget) matches
      tagged Valid (tagged AvalonWrite {}) : return True;
      default : return False;
    endcase;
    method avm_byteenable = case (fromMaybe(?,req.wget)) matches
      tagged AvalonRead  { byteenable: .be } : return be;
      tagged AvalonWrite { byteenable: .be } : return be;
    endcase;
    method avm_burstcount = case (fromMaybe(?,req.wget)) matches
      tagged AvalonRead  { burstcount: .c } : return c;
      tagged AvalonWrite { burstcount: .c } : return c;
    endcase;
  endinterface

  interface Server server;
    interface Put request;
      method Action put(x) if (reqReady);
        req.wset(x);
      endmethod
    endinterface
    interface response = toGet(resp);
  endinterface

endmodule


//External interface for an Avalon Slave device.
(* always_ready, always_enabled *)
interface AvalonSlaveExtVerbose#(
  type dataT,
  type addressT,
  numeric type burstWidth,
  numeric type byteEnableWidth
);
  method dataT  avs_readdata;
  method Bool   avs_readdatavalid;
  method Bool   avs_waitrequest;
  method Action avs(
    dataT writedata,
    addressT address,
    Bool read,
    Bool write,
    Bit#(byteEnableWidth) byteenable,
    UInt#(burstWidth) burstcount
  );
endinterface

typedef AvalonSlaveExtVerbose#(dataT,addressT,burstWidth,TMul#(byteEnable,TDiv#(SizeOf#(dataT),8)))
  AvalonSlaveExt#(type dataT,type addressT,numeric type burstWidth,numeric type byteEnable);

interface AvalonSlave#(
  type dataT,
  type addressT,
  numeric type burstWidth,
  numeric type byteEnable
);
  interface AvalonSlaveExt#(dataT,addressT,burstWidth,byteEnable) avs;
  interface Client#(
    AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable),
    AvalonMMResponse#(dataT)
  ) client;
endinterface

module mkAvalonSlave(
  AvalonSlave#(dataT,addressT,burstWidth,byteEnable))
provisos(
  Bits#(dataT,dataWidth),
  Bits#(addressT,addressWidth),
  Mul#(8,dataBytes,dataWidth)
);

  //Should be UGBypassFIFO
  FIFOF#(AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable))
    req <- mkGLFIFOF(True,False);

  RWire#(dataT) resp <- mkRWire;

  interface AvalonSlaveExtVerbose avs;
    method avs_readdata = fromMaybe(?,resp.wget);
    method avs_readdatavalid = isValid(resp.wget);
    method avs_waitrequest = !req.notFull;
    method Action avs(writedata,address,read,write,byteenable,burstcount);
      if (read) begin
        req.enq(AvalonRead{
          address    : address,
          byteenable : byteenable,
          burstcount : burstcount
        });
      end else
      if (write) begin
        req.enq(AvalonWrite{
          address    : address,
          writedata  : writedata,
          byteenable : byteenable,
          burstcount : burstcount
        });
      end
    endmethod
  endinterface

  interface Client client;
    interface Get request;
      method ActionValue#(
        AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable)
      ) get();
        req.deq();
        return req.first;
      endmethod
    endinterface
    interface response = toPut(resp);
  endinterface

endmodule


interface AvalonBuffer#(
  numeric type reqDepth,
  numeric type respDepth,
  type dataT,
  type addressT,
  numeric type burstWidth,
  numeric type byteEnable
);
  interface Server#(
    AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable),
    AvalonMMResponse#(dataT)
  ) server;
  interface Client#(
    AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable),
    AvalonMMResponse#(dataT)
  ) client;
endinterface

typedef UInt#(TLog#(TAdd#(a,1))) Range#(numeric type a);

module mkAvalonBuffer(
  AvalonBuffer#(reqDepth,respDepth,dataT,addressT,burstWidth,byteEnable))
provisos(
  Bits#(dataT,dataWidth),
  Bits#(addressT,addressWidth),
  Add#(burstWidth, _, TLog#(TAdd#(respDepth, 1)))
);

  FIFO#(AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable))
    requestBuffer <- mkSizedFIFO(valueof(reqDepth));

  FIFOCountIfc#(dataT,respDepth) responseBuffer <- mkFIFOCount;
  Reg#(Range#(respDepth)) allocated <- mkReg(0);

  Wire#(Range#(respDepth)) allocate   <- mkDWire(0);
  Wire#(Range#(respDepth)) deallocate <- mkDWire(0);
  rule updateAllocated;
    allocated <= allocated + allocate - deallocate;
  endrule

  Range#(respDepth) nextAllocation = case (requestBuffer.first) matches
    tagged AvalonRead  { burstcount: .bc } &&& (bc > 1) : return extend(bc);
    tagged AvalonRead  {} : return 1;
    tagged AvalonWrite {} : return 0;
  endcase;

  let freeSpace =
    fromInteger(valueof(respDepth)) - responseBuffer.count - allocated;

  interface Server server;
    interface request = toPut(requestBuffer);
    interface response = toGet(responseBuffer);
  endinterface
  interface Client client;
    interface Get request;
      method ActionValue#(
        AvalonMMRequest#(dataT,addressT,burstWidth,byteEnable)
      ) get() if (extend(nextAllocation) < freeSpace);
        allocate <= nextAllocation;
        requestBuffer.deq();
        return requestBuffer.first;
      endmethod
    endinterface
    interface Put response;
      method Action put(x);
        responseBuffer.enq(x);
        deallocate <= 1;
      endmethod
    endinterface
  endinterface
endmodule


endpackage
