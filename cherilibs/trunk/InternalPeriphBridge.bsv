/*-
* Copyright (c) 2014 Alexandre Joannou
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
*/

import MasterSlave::*;
import MemTypes::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;
import Assert::*;
import Debug::*;

`ifdef MEM128
  typedef 2 BusWords;
`elsif MEM64
  typedef 1 BusWords;
`else
  typedef 4 BusWords;
`endif
typedef SizeOf#(CheriPhyByteOffset) ByteOffsetSize;

interface InternalPeripheralBridge;
    interface Slave#(CheriMemRequest, CheriMemResponse) slave;
    interface Master#(CheriMemRequest64, CheriMemResponse64) master;
endinterface

typedef enum {Idle, Read, Write} BridgeState deriving (Bits, Eq);
(* synthesize *)
module mkInternalPeripheralBridge (InternalPeripheralBridge);

    FIFOF#(CheriMemRequest)     slave_req_fifo      <-  mkFIFOF1;
    FIFOF#(CheriMemResponse)    slave_resp_fifo     <-  mkBypassFIFOF;
    FIFOF#(CheriMemRequest64)   master_req_fifo     <-  mkBypassFIFOF;
    FIFOF#(CheriMemResponse64)  master_resp_fifo    <-  mkFIFOF;

    Reg#(UInt#(3))                     stop_cnt     <-  mkReg(0);
    Reg#(UInt#(3))                     req_cnt      <-  mkReg(0);
    Reg#(UInt#(3))                     resp_cnt     <-  mkReg(0);
    Reg#(Bool)                         resp_error   <-  mkReg(False);
    Reg#(Vector#(BusWords, Bit#(64)))  resp_data    <-  mkRegU;

    Reg#(BridgeState)           bridge_state        <-  mkReg(Idle);

    CheriMemRequest     reqWide = slave_req_fifo.first;
    CheriMemResponse64   resp64 = master_resp_fifo.first;

    function Bool isAligned (CheriMemRequest req) =
        case (req.operation) matches
            tagged Read .rop : begin
                Bit#(40) addr = pack(req.addr);
                case (rop.bytesPerFlit) matches
                    BYTE_1   : True;
                    BYTE_2   : (addr[0]   == 0);
                    BYTE_4   : (addr[1:0] == 0);
                    BYTE_8   : (addr[2:0] == 0);
                    BYTE_16  : (addr[3:0] == 0);
                    BYTE_32  : (addr[4:0] == 0);
                    BYTE_64  : (addr[5:0] == 0);
                    BYTE_128 : (addr[6:0] == 0);
                endcase
            end
            default : True;
        endcase;

    rule idle (bridge_state == Idle);
        debug2("periphBridge", $display("<time %0t, periphBridge> handle reqWide ", $time, fshow(reqWide)));
        dynamicAssert(isAligned(reqWide), "Unaligned accesses not supported");
        CheriMemRequest64 req64 = unpack(0);
        case (reqWide.operation) matches
            tagged Read .rop: begin
                dynamicAssert(rop.noOfFlits == 0, "Burst not supported");
                BytesPerFlit bpf = BYTE_8;
                case (rop.bytesPerFlit)
                    BYTE_1, BYTE_2, BYTE_4, BYTE_8: begin
                        bpf = rop.bytesPerFlit;
                        stop_cnt <= 1;
                    end
                    BYTE_16: stop_cnt <= 2;
                    BYTE_32: stop_cnt <= 4;
                    default:
                        dynamicAssert(False, "Flit width not supported");
                endcase
                req64.addr = unpack(pack(reqWide.addr));
                req64.masterID = reqWide.masterID;
                req64.transactionID = reqWide.transactionID;
                req64.operation = tagged Read {
                    uncached: rop.uncached,
                    linked: rop.linked,
                    noOfFlits: 0,
                    bytesPerFlit: bpf
                };
                bridge_state <= Read;
            end
            tagged Write . wop: begin
                dynamicAssert(wop.last, "Burst not supported");
                req64.addr = unpack({reqWide.addr.lineNumber,0});
                req64.masterID = reqWide.masterID;
                req64.transactionID = reqWide.transactionID;
                req64.operation = tagged Write {
                    uncached: wop.uncached,
                    conditional: wop.conditional,
                    byteEnable: take(wop.byteEnable),
                    data: Data{
                        `ifdef CAP
                          cap: unpack(0),
                        `endif
                        data: wop.data.data[63:0]
                    },
                    last: True
                };
                bridge_state <= Write;
                stop_cnt <= 4;
            end
            default:
                dynamicAssert(False, "Only Read and Write requests are supported");
        endcase

        req_cnt    <= 1;
        resp_cnt   <= 0;
        resp_data  <= unpack(0);
        resp_error <= False;

        master_req_fifo.enq(req64);
        debug2("periphBridge", $display("<time %0t, periphBridge> send req64 ", $time, fshow(req64)));

    endrule

    rule read_next ( reqWide.operation matches tagged Read .rop &&& 
                     bridge_state == Read &&& 
                     req_cnt != stop_cnt);
        CheriMemRequest64 req64;
        UInt#(40) tmp = zeroExtend(req_cnt);
        tmp = tmp << 3;
        req64.addr = unpack({pack(reqWide.addr.lineNumber),0} + pack(tmp));
        req64.masterID = reqWide.masterID;
        req64.transactionID = reqWide.transactionID;
        req64.operation = tagged Read {
            uncached: rop.uncached,
            linked: rop.linked,
            noOfFlits: 0,
            bytesPerFlit: BYTE_8
        };

        req_cnt <= req_cnt + 1;
        master_req_fifo.enq(req64);
        debug2("periphBridge", $display("<time %0t, periphBridge> send req64 ", $time, fshow(req64)));

        /*
        if ((rop.bytesPerFlit == BYTE_16 && req_cnt == 0) ||
            (rop.bytesPerFlit == BYTE_32 && req_cnt == 2))
            bridge_state <= ReadWait;*/
    endrule

    rule read_wait ( resp64.operation matches tagged Read .rop64 &&&
                     reqWide.operation matches tagged Read .ropWide &&& 
                     bridge_state == Read);
        
        Vector#(BusWords, Bit#(64)) send_data = unpack(pack(resp_data));
        Bit#(64) recv_data = rop64.data.data;
        Bool error = resp_error || (resp64.error == SlaveError);
            
        Integer top = valueOf(ByteOffsetSize)-1;
        if (top >= 3) begin
          Bit#(TLog#(BusWords)) index = reqWide.addr.byteOffset[top:3] + truncate(pack(resp_cnt));
          send_data[index] = recv_data;
          debug2("periphBridge", $display("<time %0t, periphBridge> index %d, recv resp64 ", $time, index, fshow(resp64)));
        end else send_data[0] = recv_data;

        master_resp_fifo.deq;
        resp_cnt <= resp_cnt + 1;
        resp_data <= send_data;
        resp_error <= error;

        if (resp_cnt == stop_cnt-1) begin
            CheriMemResponse respWide;
            respWide.masterID = reqWide.masterID;
            respWide.transactionID = reqWide.transactionID;
            respWide.error = error ? SlaveError : NoError;
            respWide.operation = tagged Read {
                data: Data{
                    `ifdef CAP
                      cap: unpack(0),
                    `endif
                    data: pack(send_data)
                },
                last: True
            };
            slave_resp_fifo.enq(respWide);
            debug2("periphBridge", $display("<time %0t, periphBridge> send respWide ", $time, fshow(respWide)));
            slave_req_fifo.deq;
            bridge_state <= Idle;
        end
    endrule

    rule write_next ( reqWide.operation matches tagged Write .wop &&& 
                      bridge_state == Write &&& 
                      req_cnt != stop_cnt);
        CheriMemRequest64 req64;
        UInt#(40) tmp = zeroExtend(req_cnt);
        tmp = tmp << 3;
        req64.addr = unpack({pack(reqWide.addr.lineNumber),0} + pack(tmp));
        req64.masterID = reqWide.masterID;
        req64.transactionID = reqWide.transactionID;

        UInt#(8) bigBase = (zeroExtend(req_cnt) << 6);
        Vector#(BusWords,Vector#(8, Bool)) bees = unpack(pack(wop.byteEnable));
        req64.operation = tagged Write {
            uncached: wop.uncached,
            conditional: wop.conditional,
            byteEnable: bees[req_cnt],
            data: Data{
                `ifdef CAP
                  cap: unpack(0),
                `endif
                data: wop.data.data[bigBase+63:bigBase]
            },
            last: True
        };

        req_cnt <= req_cnt + 1;
        master_req_fifo.enq(req64);
        debug2("periphBridge", $display("<time %0t, periphBridge> send req64 ", $time, fshow(req64)));
    endrule

    rule write_wait (bridge_state == Write);
        Bool error = resp_error || (resp64.error == SlaveError);
        master_resp_fifo.deq;
        debug2("periphBridge", $display("<time %0t, periphBridge> recv resp64 ", $time, fshow(resp64)));
        if(resp64.operation matches tagged Read .rop64) dynamicAssert(False, "Expecting write response");

        resp_cnt <= resp_cnt + 1;
        resp_error <= error;

        if (resp_cnt == stop_cnt-1) begin
            CheriMemResponse respWide;
            respWide.masterID = reqWide.masterID;
            respWide.transactionID = reqWide.transactionID;
            respWide.error = error ? SlaveError : NoError;
            respWide.operation = tagged Write;
            slave_resp_fifo.enq(respWide);
            debug2("periphBridge", $display("<time %0t, periphBridge> send respWide ", $time, fshow(respWide)));
            slave_req_fifo.deq;
            bridge_state <= Idle;
        end
    endrule

    interface Slave slave;
        interface request  = toCheckedPut(slave_req_fifo);
        interface response = toCheckedGet(slave_resp_fifo);
    endinterface

    interface Master master;
        interface request  = toCheckedGet(master_req_fifo);
        interface response = toCheckedPut(master_resp_fifo);
    endinterface

endmodule
