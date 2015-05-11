/*-
* Copyright (c) 2014 Colin Rothwell
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

import Processor::*; // The interface
import Proc::*; // The implementation
import Peripheral::*; // BlueBus interfaces and counter
import CheriAxi::*;
import BlueBusWrapper::*;
import MemTypes::*; // CORE_COUNT lives here...
import AvalonStreaming::*;
import AxiBridge::*;
import TLMBridge::*;
import BeriBootMem::*;
import Interconnect::*;
import NumberTypes::*;

import TLM3::*;
import Axi::*;
import Vector::*;
import BRAM::*;
import Connectable::*;

`include "TLM.defines"
`include "CheriTLM.defines"
`include "parameters.bsv"

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
    interface AxiWrMaster#(`TLM_PRM_TRACE) trace_write_master;
    (* prefix = "axm_trace" *)
    interface AxiRdMaster#(`TLM_PRM_TRACE) trace_read_master;
    `endif

    interface DebugSinks debug_stream_sinks;
    interface DebugSources debug_stream_sources;

    (* always_ready, always_enabled *)
    method Action irq(Bit#(32) irqs);

    (* always_ready, always_enabled *)
    method Bool reset_n_out();
endinterface

(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkTopAxi(TopAxi);

    Reg#(Bit#(32)) qsysIrqs <- mkReg(0);

    Processor processor <- mkCheri();

    // Construct crossbar, fifofs and transactors for CHERI.

    CheriRdMasterXActor internalRdXActor <- mkAxiRdMaster(8);
    CheriWrMasterXActor internalWrXActor <- mkAxiWrMaster(8, False);
    let internalSlave <- mkSplitTLMToInterconnectSlave(
            internalRdXActor.tlm, internalWrXActor.tlm);

    CheriRdMasterXActor externalRdXActor <- mkAxiRdMaster(8);
    CheriWrMasterXActor externalWrXActor <- mkAxiWrMaster(8, True);
    let externalSlave <- mkSplitTLMToInterconnectSlave(
            externalRdXActor.tlm, externalWrXActor.tlm);

    Vector#(1, CheriInterconnectMaster) interconnectMasters = newVector();
    interconnectMasters[0] = processor.extMemory;

    Vector#(2, CheriInterconnectSlave) interconnectSlaves = newVector();
    interconnectSlaves[0] = externalSlave;
    interconnectSlaves[1] = internalSlave;

    // helper function to route a packet to the right output
    function Maybe#(BuffIndex#(1, 2)) route (CheriTLMReq r);
        return tagged Valid BuffIndex{
            bix: (  pack(getRoutingField(r))[30:23] == 8'hff ||             // bluespec peripherals
                    pack(getRoutingField(r))[30:17] == 14'h2000) ? 1 : 0    // boot memory
        };
    endfunction
    
    // Bus 
    mkSingleMasterOrderedBus(
        processor.extMemory, 
        interconnectSlaves, route, 8 // transactions.
    );


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

    function Bool matchBaseAndMask(
            CheriTLMAddr base, CheriTLMAddr mask, CheriTLMAddr addr);
        return (addr & mask) == base;
    endfunction

    // Construct Boot Memory.
    // TODO: Use an axtual banked BRAM.

    /*BRAM_Configure bootMemCfg = defaultValue();*/
    /*bootMemCfg.loadFormat = tagged Hex "mem.hex"; // boot data*/
    /*BRAM2PortBE#(Bit#(11), Bit#(256), 32) bootMem <- mkBRAM2ServerBE(bootMemCfg);*/
    BRAM2PortBE#(Bit#(11), Bit#(256), 32) bootMem <- mkSplitBootMem();
    let matchBootMem = matchBaseAndMask(`BERI_ROM_BASE, `BERI_ROM_MASK);
    CheriTLMRecv tlmRdBootMem <- mkTLMBRAMBE(bootMem.portA);
    CheriTLMRecv tlmWrBootMem <- mkTLMBRAMBE(bootMem.portB);
    CheriRdSlaveXActor bootMemRdXActor <- mkAxiRdSlave(False, matchBootMem);
    CheriWrSlaveXActor bootMemWrXActor <- mkAxiWrSlave(False, matchBootMem);
    let bootMemReadConn <- mkConnection(bootMemRdXActor.tlm, tlmRdBootMem);
    let bootMemWriteConn <- mkConnection(bootMemWrXActor.tlm, tlmWrBootMem);

    // Construct Counter, for cache debugging etc.

    let bbCounter <- mkCountPerif();
    let counter <- mkBlueBusPeripheralToTLM(
        bbCounter, `CHERI_COUNT_BASE, `CHERI_COUNT_WIDTH);
    CheriRdSlaveXActor counterXActor <- mkAxiRdSlave(False, counter.matchAddress);
    let counterConn <- mkConnection(counterXActor.tlm, counter.peripheral.read);

    // Construct PICs.

    `ifndef MULTI
        let pic <- mkBlueBusPeripheralToTLM(
            processor.pic[0], `CHERI_PIC_BASE_0, `CHERI_PIC_WIDTH);
        let picAxi <- mkTLMReadWriteRecvToAxi(pic.peripheral, pic.matchAddress);
    `else
        let pic_0 <- mkBlueBusPeripheralToTLM(
            processor.pic[0], `CHERI_PIC_BASE_0, `CHERI_PIC_WIDTH);
        let picAxi_0 <- mkTLMReadWriteRecvToAxi(pic_0.peripheral, pic_0.matchAddress);
        let pic_1 <- mkBlueBusPeripheralToTLM(
            processor.pic[1], `CHERI_PIC_BASE_1, `CHERI_PIC_WIDTH);
        let picAxi_1 <- mkTLMReadWriteRecvToAxi(pic_1.peripheral, pic_1.matchAddress);
    `endif

    // Construct Read Bus.

    Vector#(1, AxiRdFabricMaster#(`TLM_PRM_CHERI)) rdMasters = newVector();
    rdMasters[0] = internalRdXActor.fabric;

    `ifndef MULTI
        Vector#(3, AxiRdFabricSlave#(`TLM_PRM_CHERI)) rdSlaves = newVector();
        rdSlaves[0] = bootMemRdXActor.fabric;
        rdSlaves[1] = counterXActor.fabric;
        rdSlaves[2] = picAxi.read;
    `else
        Vector#(4, AxiRdFabricSlave#(`TLM_PRM_CHERI)) rdSlaves = newVector();
        rdSlaves[0] = bootMemRdXActor.fabric;
        rdSlaves[1] = counterXActor.fabric;
        rdSlaves[2] = picAxi_0.read;
        rdSlaves[3] = picAxi_1.read;
    `endif

    mkAxiRdBus(rdMasters, rdSlaves);

    // Construct Write Bus.

    Vector#(1, AxiWrFabricMaster#(`TLM_PRM_CHERI)) wrMasters = newVector();
    wrMasters[0] = internalWrXActor.fabric;

    `ifndef MULTI
        Vector#(2, AxiWrFabricSlave#(`TLM_PRM_CHERI)) wrSlaves = newVector();
        wrSlaves[0] = bootMemWrXActor.fabric;
        wrSlaves[1] = picAxi.write;
    `else
        Vector#(3, AxiWrFabricSlave#(`TLM_PRM_CHERI)) wrSlaves = newVector();
        wrSlaves[0] = bootMemWrXActor.fabric;
        wrSlaves[1] = picAxi_0.write;
        wrSlaves[2] = picAxi_1.write;
    `endif

    mkAxiWrBus(wrMasters, wrSlaves);

    (* fire_when_enabled, no_implicit_conditions*)
    rule irqFeedThrough;
        // blueBusIrqs (in well defined positions) grow from the top.
        // Currently there are no blueBusIrqs.
        // qsysIrqs grow from the bottom.
        processor.putIrqs(qsysIrqs);
    endrule

    method Action irq(Bit#(32) irqs);
        qsysIrqs <= irqs;
    endmethod

    method Bool reset_n_out = processor.reset_n;

    interface debug_stream_sinks = map(tpl_1, debugs);
    interface debug_stream_sources = map(tpl_2, debugs);

    interface read_master = externalRdXActor.fabric.bus;
    interface write_master = externalWrXActor.fabric.bus;

endmodule
