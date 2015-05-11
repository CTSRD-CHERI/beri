/*-
 * Copyright (c) 2010 Greg Chadwick
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Robert M. Norton
 * Copyright (c) 2013 Robert N. M. Watson
 * Copyright (c) 2013 Simon W. Moore
 * Copyright (c) 2013 Alan A. Mujumdar
 * Copyright (c) 2014 Colin Rothwell
 * Copyright (c) 2014-2015 Alexandre Joannou
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
 */

// XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
// TODO move in an other file Param.bsv, with all params for cheri build ?
`ifdef MULTI
  typedef `CORE_COUNT_IN CORE_COUNT;
`else
  typedef 1 CORE_COUNT;
`endif

typedef 8 MaxTransactions;
typedef 8 MaxNoOfFlits;
// XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX
//TODO move this to a file dedicated to cache coherency stuff ?
`ifdef MULTI
  typedef struct{ 
    Bool valid;
    Bool scResult;
    Bit#(16) coreID;
  } ScPacket deriving (Bits, Eq); 


  typedef struct {  
    Vector#(TMul#(CORE_COUNT,2), Bool) sharers;
    CheriPhyAddr addr;
  } InvalidateCache deriving (Bits, Eq, FShow); 
`endif
// XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX XXX

import Vector :: *;
import DefaultValue :: *;
import Interconnect :: *;
import MasterSlave :: *;

// physical byte address type
// CR: width is the TOTAL width of the type; this type is a clever way to allow byte
// slicing from Alexendre.
typedef struct {
    Bit#(TSub#(width,TLog#(bytePerLine)))   lineNumber;
    Bit#(TLog#(bytePerLine))                byteOffset;
} PhyByteAddress#(numeric type width, numeric type bytePerLine) deriving (Bits, Eq, Bounded, FShow);

typedef Bit#(TLog#(bytePerLine)) PhyByteOffset#(numeric type bytePerLine);
typedef Bit#(TAdd#(TLog#(bytePerLine),3)) PhyBitOffset#(numeric type bytePerLine);


// physical address for cheri
`ifdef MEM128
  typedef PhyByteAddress#(40,16) CheriPhyAddr;
  typedef PhyByteOffset#(16) CheriPhyByteOffset;
  typedef PhyBitOffset#(16)  CheriPhyBitOffset;
  BytesPerFlit cheriBusBytes = BYTE_16;
`elsif MEM64
  typedef PhyByteAddress#(40,8) CheriPhyAddr;
  typedef PhyByteOffset#(8) CheriPhyByteOffset;
  typedef PhyBitOffset#(8)  CheriPhyBitOffset;
  BytesPerFlit cheriBusBytes = BYTE_8;
`else
  typedef PhyByteAddress#(40,32) CheriPhyAddr;
  typedef PhyByteOffset#(32) CheriPhyByteOffset;
  typedef PhyBitOffset#(32)  CheriPhyBitOffset;
  BytesPerFlit cheriBusBytes = BYTE_32;
`endif
typedef PhyByteAddress#(40,8) CheriPeriphAddr;

// bytes per flit
typedef enum {
    BYTE_1      = 0,  //    8 bits
    BYTE_2      = 1,  //   16 bits
    BYTE_4      = 2,  //   32 bits
    BYTE_8      = 3,  //   64 bits
    BYTE_16     = 4,  //  128 bits
    BYTE_32     = 5,  //  256 bits
    BYTE_64     = 6,  //  512 bits
    BYTE_128    = 7   // 1024 bits
} BytesPerFlit deriving (Bits, Eq, Bounded, FShow);

// Data type
typedef struct {
    `ifdef CAP
      // is this line a capability
      Vector#(TDiv#(width,256),Bool) cap;
    `elsif CAP128
      Vector#(TDiv#(width,128),Bool) cap;
    `endif
    // actual data
    Bit#(width) data;
} Data#(numeric type width) deriving (Bits, Eq, FShow);

// what cache to target
typedef enum {
    ICache, DCache, None, L2
} WhichCache deriving (Bits, Eq, FShow);

// what cache operation to perform
typedef enum {
    CacheInvalidate,
    CacheInvalidateWriteback,
    CacheWriteback,
    CacheInvalidateIndexWriteback,
    CacheRead,
    CacheWrite,
// here only as a temporary fix for migration to the new format
    Read, //XXX
// here only as a temporary fix for migration to the new format
    Write, //XXX
// here only as a temporary fix for migration to the new format
    StoreConditional, //XXX
    CacheLoadTag,
    CacheNop
} CacheInst deriving (Bits, Eq, FShow);

// a cache operation
typedef struct {
    // what operation has to be performed
    CacheInst inst;
    // what cache is targeted
    WhichCache cache;
    // is it an index based operation
    Bool indexed;
} CacheOperation deriving (Bits, Eq, FShow);

instance DefaultValue#(CacheOperation);
    function CacheOperation defaultValue =
        CacheOperation {
            inst:   CacheNop,
            cache:  DCache,
            indexed: True
        };
endinstance

// error when routing / performing the request
typedef enum {
    NoError, BusError, SlaveError
} Error deriving (Bits, Eq, FShow);

/////////////////////////////////
// cheri memory request format //
/////////////////////////////////

typedef struct {
    // byte address
    addr_t addr;
    // master ID to identify the requester
    // XXX THIS FIELD HAS TO BE MIRRORED BY THE SLAVE XXX
    masterid_t masterID;
    // transaction ID field used to identify a unique transaction amongst
    // several outstanding transactions
    // XXX THIS FIELD HAS TO BE MIRRORED BY THE SLAVE XXX
    transactionid_t transactionID;
    // operation to be performed by the request
    union tagged {
        // read operation
        struct {
            // uncached / cached access
            Bool uncached;
            // LL / standard load
            Bool linked;
            // number of flits to be returned
            UInt#(TLog#(MaxNoOfFlits))  noOfFlits;
            // number of bytes per flit
            BytesPerFlit bytesPerFlit;
        } Read;
        struct {
            // uncached / cached access
            Bool uncached;
            // SC / standard write
            Bool conditional;
            // byte enable vector
            Vector#(TDiv#(data_width,8), Bool) byteEnable;
            // line data
            Data#(data_width) data;
            // True for the last flit of the burst
            Bool last;
        } Write;
        // for a cache operation
        CacheOperation CacheOp;
    } operation;
} MemoryRequest#(type addr_t, type masterid_t, type transactionid_t, numeric type data_width) deriving (Bits);

instance DefaultValue#(MemoryRequest#(a,b,c,d))
    provisos(Bits#(a,a_),Bits#(b,b_),Bits#(c,c_));
    function MemoryRequest#(a,b,c,d) defaultValue =
        MemoryRequest {
            addr:           unpack(0),
            masterID:       unpack(0),
            transactionID:  unpack(0),
            operation:      tagged CacheOp defaultValue
        };
endinstance

instance Routable#(MemoryRequest#(a,b,c,d), r_width)
    provisos(Bits#(a,r_width));
    function UInt#(r_width) getRoutingField (MemoryRequest#(a,b,c,d) req) =
        unpack(pack(req.addr));
    function Bool getLastField (MemoryRequest#(a,b,c,d) req) =
    req.operation matches tagged Write .wop ? wop.last : True;
endinstance

instance FShow#(MemoryRequest#(a,b,c,d))
    provisos (FShow#(a),Bits#(a,a_),Bits#(b,b_),Bits#(c,c_));
    function Fmt fshow(MemoryRequest#(a,b,c,d) req);
        case (req.operation) matches
            tagged Read .rop: return (
                $format("Read MemoryRequest - ") +
                $format("masterID: %0d", req.masterID) +
                $format(" | transactionID: %0d", req.transactionID) +
                $format(" | address: 0x%0x ",pack(req.addr), fshow(req.addr)) +
                $format(" | uncached: ") + fshow(rop.uncached) +
                $format(" | linked: ") + fshow(rop.linked) +
                $format(" | noOfFlits(-1): %0d", rop.noOfFlits) +
                $format(" | bytesPerFlit: ") + fshow(rop.bytesPerFlit)
            );
            tagged Write .wop: return (
                $format("Write MemoryRequest - ") +
                $format("masterID: %0d", req.masterID) +
                $format(" | transactionID: %0d", req.transactionID) +
                $format(" | address: 0x%0x ",pack(req.addr), fshow(req.addr)) +
                $format(" | uncached: ") + fshow(wop.uncached) +
                $format(" | conditional: ") + fshow(wop.conditional) +
                $format(" | byteEnable: %0x", pack(wop.byteEnable)) +
                $format(" | last: ") + fshow(wop.last) +
                $format(" | data: ") + fshow(wop.data)
            );
            tagged CacheOp .cop: return (
                $format("CacheOp MemoryRequest - ") +
                $format("masterID: %0d", req.masterID) +
                $format(" | transactionID: %0d", req.transactionID) +
                $format(" | address: 0x%0x ",pack(req.addr), fshow(req.addr)) +
                $format(" | cache operation: ") + fshow(cop)
            );
            default: return (
                $format("Unknown MemoryRequest")
            );
        endcase
    endfunction
endinstance

typedef Bit#(4) CheriMasterID;
typedef Bit#(4) CheriTransactionID;

`ifdef MEM64
  typedef 64 CheriDataWidth;
`elsif MEM128
  typedef 128 CheriDataWidth;
`else
  typedef 256 CheriDataWidth;
`endif
typedef Data#(CheriDataWidth) CheriData;
typedef MemoryRequest#(CheriPhyAddr,CheriMasterID,CheriTransactionID,CheriDataWidth) CheriMemRequest;
typedef MemoryRequest#(CheriPeriphAddr,CheriMasterID,CheriTransactionID,64)  CheriMemRequest64;

//////////////////////////////////
// cheri memory response format //
//////////////////////////////////

typedef struct {
    // master ID to identify the requester
    // XXX THIS FIELD HAS TO BE MIRRORED BY THE SLAVE XXX
    masterid_t masterID;
    // transaction ID field used to identify a unique transaction amongst
    // several outstanding transactions
    // XXX THIS FIELD HAS TO BE MIRRORED BY THE SLAVE XXX
    transactionid_t transactionID;
    // error being returned
    Error error;
    // content of the response
    union tagged {
        struct {
            // line data
            Data#(data_width) data;
            // True for the last flit of the burst
            Bool last;
        } Read;
        // no information for write responses
        void Write;
        // True for a success
        Bool SC;
    } operation;
} MemoryResponse#(type masterid_t, type transactionid_t, numeric type data_width) deriving (Bits);

instance DefaultValue#(MemoryResponse#(a,b,c))
    provisos(Bits#(a,a_),Bits#(b,b_));
    function MemoryResponse#(a,b,c) defaultValue =
        MemoryResponse {
            masterID:       unpack(0),
            transactionID:  unpack(0),
            error:          NoError,
            operation:      tagged Write
        };
endinstance

instance Routable#(MemoryResponse#(a,b,c), r_width)
    provisos(Bits#(a,r_width));
    function UInt#(r_width) getRoutingField (MemoryResponse#(a,b,c) rsp) =
        unpack(pack(rsp.masterID));
    function Bool getLastField (MemoryResponse#(a,b,c) rsp) =
    rsp.operation matches tagged Read .rop ? rop.last : True;
endinstance

instance FShow#(MemoryResponse#(a,b,c))
    provisos(Bits#(a,a_),Bits#(b,b_));
    function Fmt fshow(MemoryResponse#(a,b,c) rsp);
        case (rsp.operation) matches
            tagged Read .rop: return (
                $format("Read MemoryResponse - ") +
                $format("masterID: %0d", rsp.masterID) +
                $format(" | transactionID: %0d", rsp.transactionID) +
                $format(" | error: ") + fshow(rsp.error) +
                $format(" | last: ") + fshow(rop.last) +
                $format(" | data: ") + fshow(rop.data)
            );
            tagged Write .wop: return (
                $format("Write MemoryResponse - ") +
                $format("masterID: %0d", rsp.masterID) +
                $format(" | transactionID: %0d", rsp.transactionID) +
                $format(" | error: ") + fshow(rsp.error)
            );
            tagged SC .scop: return (
                $format("SC MemoryResponse - ") +
                $format("masterID: %0d", rsp.masterID) +
                $format(" | transactionID: %0d | ", rsp.transactionID) +
                $format(" | error: ") + fshow(rsp.error) +
                $format(" | success: ") + fshow(scop)
            );
            default: return (
                $format("Unknown MemoryResponse")
            );
        endcase
    endfunction
endinstance

typedef MemoryResponse#(CheriMasterID,CheriTransactionID,CheriDataWidth) CheriMemResponse;
typedef MemoryResponse#(CheriMasterID,CheriTransactionID,64)  CheriMemResponse64;

typedef Slave#(CheriMemRequest64, CheriMemResponse64)   CheriPeriphSlave;
typedef Slave#(CheriMemRequest, CheriMemResponse)       CheriSlave;

typedef Master#(CheriMemRequest64, CheriMemResponse64)  CheriPeriphMaster;
typedef Master#(CheriMemRequest, CheriMemResponse)      CheriMaster;
