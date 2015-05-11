/*-
 * Copyright (c) 2013, 2014 Alexandre Joannou
 * All rights reserved.
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
 */

package AsymmetricBRAM;

import FIFO :: *;
import SpecialFIFOs :: *;
import ConfigReg :: * ;
import Vector :: * ;

// Interface to the asymmetric ram
interface AsymmetricBRAM#(  type rAddrT, type rDataT,
                            type wAddrT, type wDataT);
    method Action read(rAddrT read_addr); // post a read request
    method ActionValue#(rDataT) getRead(); // get the read response
    method Action write(wAddrT write_addr, wDataT write_data); // post a write request
endinterface

// Interface to the verilog module (using an altsyncram component)
interface VAsymBRAMIfc#(    type rAddrT,type rDataT,
                            type wAddrT, type wDataT);
    method Action read(rAddrT read_addr);
    method rDataT getRead();
    method Action write(wAddrT write_addr, wDataT write_data);
endinterface

// Wrapper for the verilog
import "BVI" AsymmetricBRAM =
module vAsymBRAM#(Bool hasOutputRegister)
                 (VAsymBRAMIfc#(raddr_t, rdata_t, waddr_t, wdata_t))
    provisos(
        Bits#(raddr_t, raddr_sz),
        Bits#(rdata_t, rdata_sz),
        Bits#(waddr_t, waddr_sz),
        Bits#(wdata_t, wdata_sz)
    );

    default_clock (CLK);
    default_reset no_reset;

    parameter   PIPELINED   = Bit#(1)'(pack(hasOutputRegister));
    parameter   WADDR_WIDTH = valueOf(waddr_sz);
    parameter   WDATA_WIDTH = valueOf(wdata_sz);
    parameter   RADDR_WIDTH = valueOf(raddr_sz);
    parameter   RDATA_WIDTH = valueOf(rdata_sz);
    parameter   MEMSIZE     = valueOf(TExp#(raddr_sz));

    method read(RADDR) enable(REN);
    method RDATA getRead();
    method write(WADDR,WDATA) enable(WEN);

    //schedule (getRead) SBR (read, write);
    schedule (read)  C (read);
    schedule (write) C (write);
    schedule (getRead) CF (getRead);
    schedule (write) CF (read);

endmodule

module mkAsymmetricBRAM#(Bool hasOutputRegister, Bool hasForwarding)
                               (AsymmetricBRAM#(raddr_t, rdata_t, waddr_t, wdata_t))
    provisos(
        Bits#(raddr_t, raddr_sz),
        Bits#(rdata_t, rdata_sz),
        Bits#(waddr_t, waddr_sz),
        Bits#(wdata_t, wdata_sz),
        Div#(wdata_sz,rdata_sz,ratio),
        Log#(ratio,offset_sz),
        Add#(waddr_sz,offset_sz,raddr_sz),
        Bits#(Vector#(ratio, rdata_t), wdata_sz)
    );
    AsymmetricBRAM#(raddr_t, rdata_t, waddr_t, wdata_t) ret_ifc;
    `ifndef BLUESIM
        ret_ifc <- mkAsymmetricBRAMVerilog(hasOutputRegister, hasForwarding);
    `else
        ret_ifc <- mkAsymmetricBRAMBluesim(hasOutputRegister, hasForwarding);
    `endif
    return ret_ifc;
endmodule

module mkAsymmetricBRAMVerilog#(Bool hasOutputRegister, Bool hasForwarding)
                               (AsymmetricBRAM#(raddr_t, rdata_t, waddr_t, wdata_t))
    provisos(
        Bits#(raddr_t, raddr_sz),
        Bits#(rdata_t, rdata_sz),
        Bits#(waddr_t, waddr_sz),
        Bits#(wdata_t, wdata_sz),
        Div#(wdata_sz,rdata_sz,ratio),
        Log#(ratio,offset_sz),
        Add#(waddr_sz,offset_sz,raddr_sz),
        Bits#(Vector#(ratio, rdata_t), wdata_sz)
    );

    VAsymBRAMIfc#(raddr_t, rdata_t, waddr_t, wdata_t) bram <- vAsymBRAM(hasOutputRegister);
    Reg#(wdata_t)                  lastWriteData <- mkConfigReg(?);
    Reg#(raddr_t)                  lastReadAddr  <- mkConfigReg(?);
    Reg#(waddr_t)                  lastWriteAddr <- mkConfigReg(?);
    Vector#(ratio,rdata_t) wdata_vector = unpack(pack(lastWriteData));

    method Action read(addr);
        bram.read(addr);
        lastReadAddr <= addr;
    endmethod

    method ActionValue#(rdata_t) getRead;
        if ((hasForwarding) &&
            (pack(lastReadAddr)[valueOf(TSub#(raddr_sz,1)):valueOf(offset_sz)] == pack(lastWriteAddr))) begin
            Bit#(offset_sz) offset = truncate(pack(lastReadAddr));
            return wdata_vector[offset];
        end
        else
            return bram.getRead;
    endmethod

    method Action write(addr, data);
        bram.write(addr, data);
	    lastWriteAddr <= addr;
	    lastWriteData <= data;
    endmethod
endmodule

import "BDPI" mem_create    = function ActionValue#(Bit#(64)) mem_create(msize_t size, rsize_t rsize, wsize_t wsize)
                              provisos (Bits#(msize_t, msize_sz),
                                        Bits#(rsize_t, rsize_sz),
                                        Bits#(wsize_t, wsize_sz));
import "BDPI" mem_clean     = function Action mem_clean(Bit#(64) mem_ptr);
import "BDPI" mem_read      = function ActionValue#(rdata_t) mem_read(Bit#(64) mem_ptr, raddr_t raddr)
                              provisos (Bits#(raddr_t, raddr_sz),
                                        Bits#(rdata_t, rdata_sz));
import "BDPI" mem_write     = function Action mem_write(Bit#(64) mem_ptr, waddr_t waddr, wdata_t wdata)
                              provisos (Bits#(waddr_t, waddr_sz),
                                        Bits#(wdata_t, wdata_sz));

module mkAsymmetricBRAMBluesim#(Bool hasOutputRegister, Bool hasForwarding)
                               (AsymmetricBRAM#(raddr_t, rdata_t, waddr_t, wdata_t))
    provisos(
        Bits#(raddr_t, raddr_sz),
        Bits#(rdata_t, rdata_sz),
        Bits#(waddr_t, waddr_sz),
        Bits#(wdata_t, wdata_sz),
        Div#(wdata_sz,rdata_sz,ratio),
        Log#(ratio,offset_sz),
        Add#(waddr_sz,offset_sz,raddr_sz),
        Bits#(Vector#(ratio, rdata_t), wdata_sz)
    );

    Reg#(Bit#(64))  mem_ptr         <- mkRegU();
    Reg#(Bool)      isInitialized   <- mkReg(False);
    Wire#(raddr_t)  newReadAddr     <- mkWire();
    PulseWire       newWrite        <- mkPulseWire();
    Reg#(Bool)      pendingWrite    <- mkReg(False);
    Reg#(waddr_t)   lastWriteAddr   <- mkConfigReg(?);
    Reg#(wdata_t)   lastWriteData   <- mkConfigReg(?);
    Reg#(raddr_t)   lastReadAddr    <- mkConfigReg(?);
    Reg#(rdata_t)   readOutput      <- mkConfigReg(?);
    Reg#(rdata_t)   regReadOutput   <- mkConfigReg(?);
    Vector#(ratio,rdata_t) wdata_vector = unpack(pack(lastWriteData));

    rule do_registered_read (isInitialized);
        regReadOutput <= readOutput;
    endrule

    (* execution_order = "do_write, do_read" *)
    rule do_read (isInitialized);
        lastReadAddr    <= newReadAddr;
        rdata_t rdata   <- mem_read(mem_ptr, newReadAddr);
        readOutput      <= rdata;
    endrule

    rule do_write (isInitialized);
        if (pendingWrite) mem_write(mem_ptr, lastWriteAddr, lastWriteData);
	    pendingWrite <= False || newWrite;
    endrule

    rule do_init (!isInitialized);
        let tmp <- mem_create(fromInteger(valueOf(TExp#(raddr_sz))),
                              fromInteger(valueOf(rdata_sz)),
                              fromInteger(valueOf(wdata_sz)));
        mem_ptr <= tmp;
        isInitialized <= True;
    endrule

    method Action read(addr) if (isInitialized);
        newReadAddr <= addr;
    endmethod

    method ActionValue#(rdata_t) getRead if (isInitialized);
        if ((hasForwarding) &&
            (pack(lastReadAddr)[valueOf(TSub#(raddr_sz,1)):valueOf(offset_sz)] == pack(lastWriteAddr))) begin
            Bit#(offset_sz) offset = truncate(pack(lastReadAddr));
            return wdata_vector[offset];
        end
        else begin
            if (!hasOutputRegister) return readOutput;
            else return regReadOutput;
        end
    endmethod

    method Action write(addr, data) if (isInitialized);
	    newWrite.send();
	    lastWriteAddr   <= addr;
	    lastWriteData   <= data;
    endmethod

endmodule

endpackage
