/*-
* Copyright (c) 2014 Colin Rothwell
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

import Axi::*;
import TLM3::*;

`include "TLM.defines"

interface AxiRdBridge#(`TLM_PRM_DCL);
    (* always_ready, always_enabled *)
    interface AxiRdFabricMaster#(`TLM_PRM) master;
    (* always_ready, always_enabled *)
    interface AxiRdFabricSlave#(`TLM_PRM) slave;
endinterface

module mkAxiRdBridge
        #(function Bool addrMatch(Bit#(addr_size) a))
        (AxiRdBridge#(`TLM_PRM));

    Wire#(Bit#(id_size))    arIdWire    <- mkBypassWire();
    Wire#(Bit#(addr_size))  arAddrWire  <- mkBypassWire();
    Wire#(UInt#(4))         arLenWire   <- mkBypassWire();
    Wire#(TLMBSize)         arSizeWire  <- mkBypassWire();
    Wire#(AxiBurst)         arBurstWire <- mkBypassWire();
    Wire#(TLMLock)          arLockWire  <- mkBypassWire();
    Wire#(AxiCache)         arCacheWire <- mkBypassWire();
    Wire#(AxiProt)          arProtWire  <- mkBypassWire();
    Wire#(Bool)             arValidWire <- mkBypassWire();
    Wire#(Bool)             arReadyWire <- mkBypassWire();

    Wire#(Bool)             rReadyWire  <- mkBypassWire();
    Wire#(Bit#(id_size))    rIdWire     <- mkBypassWire();
    Wire#(Bit#(data_size))  rDataWire   <- mkBypassWire();
    Wire#(AxiResp)          rRespWire   <- mkBypassWire();
    Wire#(Bool)             rLastWire   <- mkBypassWire();
    Wire#(Bool)             rValidWire  <- mkBypassWire();

    interface AxiRdFabricMaster master;
        interface AxiRdMaster bus;
            method arID = arIdWire._read;
            method arADDR = arAddrWire._read;
            method arLEN = arLenWire._read;
            method arSIZE = arSizeWire._read;
            method arBURST = arBurstWire._read;
            method arLOCK = arLockWire._read;
            method arCACHE = arCacheWire._read;
            method arPROT = arProtWire._read;
            method arVALID = arValidWire._read;
            method arREADY = arReadyWire._write;

            method rREADY = rReadyWire._read;
            method rID = rIdWire._write;
            method rDATA = rDataWire._write;
            method rRESP = rRespWire._write;
            method rLAST = rLastWire._write;
            method rVALID = rValidWire._write;
        endinterface
    endinterface

    interface AxiRdFabricSlave slave;
        interface AxiRdSlave bus;
            method arID = arIdWire._write;
            method arADDR = arAddrWire._write;
            method arLEN = arLenWire._write;
            method arSIZE = arSizeWire._write;
            method arBURST = arBurstWire._write;
            method arLOCK = arLockWire._write;
            method arCACHE = arCacheWire._write;
            method arPROT = arProtWire._write;
            method arVALID = arValidWire._write;
            method arREADY = arReadyWire._read;

            method rREADY = rReadyWire._write;
            method rID = rIdWire._read;
            method rDATA = rDataWire._read;
            method rRESP = rRespWire._read;
            method rLAST = rLastWire._read;
            method rVALID = rValidWire._read;
        endinterface

        method addrMatch = addrMatch;
    endinterface

endmodule 

interface AxiWrBridge#(`TLM_PRM_DCL);
    (* always_ready, always_enabled *)
    interface AxiWrFabricMaster#(`TLM_PRM) master;
    (* always_ready, always_enabled *)
    interface AxiWrFabricSlave#(`TLM_PRM) slave;
endinterface

module mkAxiWrBridge
        #(function Bool addrMatch(Bit#(addr_size) a))
        (AxiWrBridge#(`TLM_PRM))
        provisos (Div#(data_size, 8, strb_size));

    Wire#(Bit#(id_size))    awIdWire    <- mkBypassWire();
    Wire#(Bit#(addr_size))  awAddrWire  <- mkBypassWire();
    Wire#(UInt#(4))         awLenWire   <- mkBypassWire();
    Wire#(TLMBSize)         awSizeWire  <- mkBypassWire();
    Wire#(AxiBurst)         awBurstWire <- mkBypassWire();
    Wire#(TLMLock)          awLockWire  <- mkBypassWire();
    Wire#(AxiCache)         awCacheWire <- mkBypassWire();
    Wire#(AxiProt)          awProtWire  <- mkBypassWire();
    Wire#(Bool)             awValidWire <- mkBypassWire();
    Wire#(Bool)             awReadyWire <- mkBypassWire();

    Wire#(Bit#(id_size))    wIdWire     <- mkBypassWire();
    Wire#(Bit#(data_size))  wDataWire   <- mkBypassWire();
    Wire#(Bit#(strb_size))  wStrbWire   <- mkBypassWire();
    Wire#(Bool)             wLastWire   <- mkBypassWire();
    Wire#(Bool)             wValidWire  <- mkBypassWire();
    Wire#(Bool)             wReadyWire  <- mkBypassWire();

    Wire#(Bool)             bReadyWire  <- mkBypassWire();
    Wire#(Bit#(id_size))    bIdWire     <- mkBypassWire();
    Wire#(AxiResp)          bRespWire   <- mkBypassWire();
    Wire#(Bool)             bValidWire  <- mkBypassWire();

    interface AxiWrFabricMaster master;
        interface AxiWrMaster bus;
            method awID = awIdWire._read;
            method awADDR = awAddrWire._read;
            method awLEN = awLenWire._read;
            method awSIZE = awSizeWire._read;
            method awBURST = awBurstWire._read;
            method awLOCK = awLockWire._read;
            method awCACHE = awCacheWire._read;
            method awPROT = awProtWire._read;
            method awVALID = awValidWire._read;
            method awREADY = awReadyWire._write;

            method wID = wIdWire._read;
            method wDATA = wDataWire._read;
            method wSTRB = wStrbWire._read;
            method wLAST = wLastWire._read;
            method wVALID = wValidWire._read;
            method wREADY = wReadyWire._write;

            method bREADY = bReadyWire._read;
            method bID = bIdWire._write;
            method bRESP = bRespWire._write;
            method bVALID = bValidWire._write;
        endinterface
    endinterface

    interface AxiWrFabricSlave slave;
        interface AxiWrSlave bus;
            method awID = awIdWire._write;
            method awADDR = awAddrWire._write;
            method awLEN = awLenWire._write;
            method awSIZE = awSizeWire._write;
            method awBURST = awBurstWire._write;
            method awLOCK = awLockWire._write;
            method awCACHE = awCacheWire._write;
            method awPROT = awProtWire._write;
            method awVALID = awValidWire._write;
            method awREADY = awReadyWire._read;

            method wID = wIdWire._write;
            method wDATA = wDataWire._write;
            method wSTRB = wStrbWire._write;
            method wLAST = wLastWire._write;
            method wVALID = wValidWire._write;
            method wREADY = wReadyWire._read;

            method bREADY = bReadyWire._write;
            method bID = bIdWire._read;
            method bRESP = bRespWire._read;
            method bVALID = bValidWire._read;
        endinterface

        method addrMatch = addrMatch;
    endinterface
endmodule
