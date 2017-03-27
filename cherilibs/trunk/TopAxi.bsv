/*-
* Copyright (c) 2014 Colin Rothwell
* Copyright (c) 2014, 2015 Alexandre Joannou
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
*/

import Processor::*; // The interface
import Proc::*; // The implementation
import Peripheral::*; // BlueBus interfaces and counter
`ifdef DMA
import DMA::*;
`else
`ifdef VIRT_DMA
import DMA::*;
`endif
`endif
import MemTypes::*;
import AvalonStreaming::*;
import AxiBridge::*;
import BeriBootMem::*;
import Interconnect::*;
import NumberTypes::*;
import MasterSlave::*;
import InternalPeriphBridge::*;
import InternalToAxi::*;
import Burst::*;

import TLM3::*;
import Axi::*;
import Vector::*;
import BRAM::*;
import Connectable::*;

`include "CheriTLM.defines"
typedef BuffIndex#(TLog#(count), count) MinimalBuffIndex#(numeric type count);


typedef Vector#(CORE_COUNT, AvalonStreamSinkPhysicalIfc#(Bit#(8))) DebugSinks;
typedef Vector#(CORE_COUNT, AvalonStreamSourcePhysicalIfc#(Bit#(8))) DebugSources;
typedef Vector#(CORE_COUNT, Tuple2#(AvalonStreamSinkPhysicalIfc#(Bit#(8)),
    AvalonStreamSourcePhysicalIfc#(Bit#(8)))) DebugPhysicals;

interface TopAxi;
    (* prefix = "axm_memory" *)
    interface AxiWrMaster#(`TLM_PRM_CHERI) write_master;
    (* prefix = "axm_memory" *)
    interface AxiRdMaster#(`TLM_PRM_CHERI) read_master;

    `ifdef TRACE
    (* prefix = "axm_trace" *)
    interface AxiWrMaster#(`PRM_TRACE) trace_write_master;
    (* prefix = "axm_trace" *)
    interface AxiRdMaster#(`PRM_TRACE) trace_read_master;
    `endif

    interface DebugSinks debug_stream_sinks;
    interface DebugSources debug_stream_sources;

    (* always_ready, always_enabled *)
    method Action irq(Bit#(32) irqs);

    (* always_ready, always_enabled *)
    method Bool reset_n_out();

    `ifdef RMA
    interface AvalonStreamSourcePhysicalIfc#(Bit#(76)) networkRx;
    interface AvalonStreamSinkPhysicalIfc#(Bit#(76)) networkTx;
    `endif
endinterface

/* TopAxi overview
 * There can also optionally be a virtualised DMA, which isn't shown.
 *                                   proc  [ DMA Master ]
 *                                    |    [      |     ]
 *                                    v    [      v     ]
 *                           --------------- bus --------------
 *                           |                                |
 *                           v                                |
 *                         burster                            |
 *                           |                                |
 *                           v                                |
 *                     periph bridge                          |   
 *                           |                                |
 *                           v                                v
 *    --------------- ordered bus ----------         -- InternalToAxi --
 *    |       |       |   [     |      ]   |         ||               ||
 *    v       v       v   [     v      ]   v         vv               vv
 * bootmem  count    pic  [ DMA Config ] null      AxiRead         AxiWrite
 *
 */

typedef 1 BaseMasterCount;
typedef 3 BasePeriphCount;

`ifdef DMA
    typedef TAdd#(1, BaseMasterCount) MasterCount1;
    typedef TAdd#(1, BasePeriphCount) PeriphCount1;
`else
    typedef BaseMasterCount MasterCount1;
    typedef BasePeriphCount PeriphCount1;
`endif
Integer dma_master_index = valueOf(BaseMasterCount);
Integer dma_periph_index = valueOf(BasePeriphCount);

`ifdef DMA_VIRT
    typedef TAdd#(1, MasterCount1) MasterCount;
    typedef TAdd#(1, PeriphCount1) PeriphCount2;
`else
    typedef MasterCount1 MasterCount;
    typedef PeriphCount1 PeriphCount2;
`endif
Integer dma_virt_master_index = valueOf(MasterCount1);
Integer dma_virt_periph_index = valueOf(PeriphCount1);

// Add CORE_COUNT for PIC
typedef TAdd#(PeriphCount2, CORE_COUNT)     PeriphCount;
typedef TLog#(PeriphCount)                  LogPeriphs;
typedef BuffIndex#(LogPeriphs, PeriphCount) PeriphBuffIndex;

(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkTopAxi(TopAxi);

    Reg#(Bit#(32)) qsysIrqs <- mkReg(0);

    Processor processor <- mkCheri();
    // Use top of masterID address space for DMA.
    `ifdef DMA
    DMA#(4) dma <- mkFourThreadDMA(DMAConfiguration {
        icacheID:   12,
        readID:     13,
        writeID:    14,
        useTLB:     False
    });
    `endif

    `ifdef DMA_VIRT
    DMA#(4) dmaVirt <- mkFourThreadDMA(DMAConfiguration {
        icacheID:   9,
        readID:     10,
        writeID:    11,
        useTLB:     True
    });
    mkConnection(processor.tlbs[0], dmaVirt.instructionTLBClient);
    mkConnection(processor.tlbs[1], dmaVirt.dataTLBClient);
    `endif

    function CheriPeriphSlave getSlave(Peripheral#(n) periph) = periph.slave;

    //////////////////////////////
    // Internal peripherals Bus //
    ///////////////////////////////////////////////////////////////////////////
    // peripherals (slaves)
    Peripheral#(0) counter <- mkCountPerif;
    Peripheral#(0) bootMem <- mkBootMem;
    Peripheral#(0) nullPer <- mkNullPerif;

    // wiring up slaves
    Vector#(PeriphCount2, CheriPeriphSlave) nonPICPeriphs = newVector();
    nonPICPeriphs[0] = nullPer.slave;
    nonPICPeriphs[1] = counter.slave;
    nonPICPeriphs[2] = bootMem.slave;
    `ifdef DMA
        nonPICPeriphs[dma_periph_index] = dma.configuration;
    `endif
    `ifdef DMA_VIRT
        nonPICPeriphs[dma_virt_periph_index] = dmaVirt.configuration;
    `endif
    Vector#(PeriphCount, CheriPeriphSlave) peripheralSlaves =
        append(nonPICPeriphs, map(getSlave, processor.pic));
    // peripheral bridge (master)
    InternalPeripheralBridge peripheralBridge <- mkInternalPeripheralBridge;
    BurstIfc burster <- mkBurst;
    mkConnection(burster.master, peripheralBridge.slave);
    // helper function to route a packet to the right output
    function Maybe#(PeriphBuffIndex) routePeripheral (CheriMemRequest64 r);
        // Layout the pics in sequential addresses starting at 7F804000
        // Data within the pic starts at bit 13, so we do a bunch of slicing
        // down to bit 14.
        // 7F8 is the bit pattern with [30:23] = '1
        let addr = pack(getRoutingField(r));
        let picNumber = addr[22:14] - 1;
        // Null peripheral by default
        PeriphBuffIndex ret = 0;
        if (addr[31:0] == 32'h7F80_0000)
            ret = 1; // null peripheral
        else if (addr[30:17] == 14'h2000)
            ret = 2; // boot memory
        `ifdef DMA
            // The DMA gets 1 MiB of address = 256 * 4K interfaces.
            else if ((addr[31:0] & ~32'hF_FFFF) == 32'h7F90_0000)
                ret = fromInteger(dma_periph_index); // dma config
        `endif
        `ifdef DMA_VIRT
            else if ((addr[31:0] & ~32'hF_FFFF) == 32'h7FA0_0000)
                ret = fromInteger(dma_virt_periph_index);
        `endif
        else if (addr[30:23] == '1 &&
                picNumber < fromInteger(valueOf(CORE_COUNT))) begin
            let rawRet = fromInteger(valueOf(PeriphCount2)) + picNumber;
            ret = unpack(truncate(rawRet));
        end
        return tagged Valid ret;
    endfunction
    // Bus
    mkSingleMasterOrderedBus(
        peripheralBridge.master,
        peripheralSlaves, routePeripheral, 32
    );

    /////////////////////////////////////
    // Axi split interface ordered Bus //
    ///////////////////////////////////////////////////////////////////////////
    // InternalToAxi translator (slave)
    InternalToAxi  axi_translator  <- mkInternalToAxi;

    //////////////
    // main Bus //
    ///////////////////////////////////////////////////////////////////////////
    Vector#(MasterCount, CheriMaster) interconnectMasters = newVector();
    interconnectMasters[0] = processor.extMemory;
    `ifdef DMA
        interconnectMasters[dma_master_index] = dma.memory;
    `endif
    `ifdef DMA_VIRT
        interconnectMasters[dma_virt_master_index] = dmaVirt.memory;
    `endif
    // wiring up slaves
    Vector#(2, CheriSlave) interconnectSlaves = newVector();
    interconnectSlaves[0] = axi_translator.slave;
    interconnectSlaves[1] = burster.slave;
    // helper function to route a packet to the right slave
    function Maybe#(BuffIndex#(1, 2)) routeSlave (CheriMemRequest r);
        // Main memory by default
        let addr = pack(getRoutingField(r));
        BuffIndex#(1,2) ret = 0;
        if ((addr[30:23] == 8'hff) || (addr[30:17] == 14'h2000))
            ret = 1;
        return tagged Valid ret;
    endfunction

    function Maybe#(MinimalBuffIndex#(MasterCount)) routeMaster(CheriMemResponse r);
        let addr = getRoutingField(r);
        if (addr == 15) // tag cache
            return tagged Valid 0;
        `ifdef DMA
        else if (12 <= addr && addr <= 14)
            return tagged Valid fromInteger(dma_master_index);
        `endif
        `ifdef DMA_VIRT
        else if (9 <= addr && addr <= 11)
            return tagged Valid fromInteger(dma_virt_master_index);
        `endif
        else
            return tagged Valid 0;
    endfunction

    // Bus
    mkBus(
        interconnectMasters, routeSlave,
        interconnectSlaves, routeMaster
    );

    ///////////
    // Debug //
    ///////////
    ///////////////////////////////////////////////////////////////////////////
    // TODO: Port and connect tracing interface.
    module mkConnectDebug
        #(Server#(Bit#(8), Bit#(8)) beriside)
        (Tuple2#(AvalonStreamSinkPhysicalIfc#(Bit#(8)),
                 AvalonStreamSourcePhysicalIfc#(Bit#(8))));

        let get <- mkAvalonStreamSink2Get();
        let put <- mkPut2AvalonStreamSource();
        mkConnection(get.rx, beriside.request);
        mkConnection(beriside.response, put.tx);

        return tuple2(get.physical, put.physical);
    endmodule

    DebugPhysicals debugs <- mapM(mkConnectDebug, processor.debugStream);
    
    (* fire_when_enabled, no_implicit_conditions*)
    rule irqFeedThrough;
        // Bluespec IRQs (in well defined positions) grow from the top.
        // The only one of these is the DMA, at interrupt 31
        // qsysIrqs grow from the bottom.
        `ifdef DMA
            Bit#(32) dmaIrq = zeroExtend(pack(dma.getIRQ())) << 31;
        `else
            Bit#(32) dmaIrq = 0;
        `endif
        processor.putIrqs(qsysIrqs | dmaIrq);
    endrule

    method Action irq(Bit#(32) irqs);
        qsysIrqs <= irqs;
    endmethod

    method Bool reset_n_out = processor.reset_n;

    interface debug_stream_sinks = map(tpl_1, debugs);
    interface debug_stream_sources = map(tpl_2, debugs);

    interface read_master  = axi_translator.read_master;
    interface write_master = axi_translator.write_master;

    `ifdef RMA
    interface networkRx = processor.networkRx;
    interface networkTx = processor.networkTx;
    `endif

endmodule
