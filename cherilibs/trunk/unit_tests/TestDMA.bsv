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

import Assert::*;
import ClientServer::*;
import Clocks::*;
import Randomizable::*;
import StmtFSM::*;
import Variadic::*;
import Vector::*;

import GetPut::*;
import MasterSlave::*;
import MemTypes::*;
import Memory::*; // For reverseBytes
import MIPS::*;
import DMA::*;
import UnitTesting::*;

// We don't care about preserving padding or invalid instruction accross
// conversion
function Bool functionallyEquivalent(Bit#(32) in, Bit#(32) out);
    let opCode = in[31:28];
    if (opCode > 6 &&& unpack(out) matches InvalidInstruction)
        return True; // Invalid Op Code
    else if (opCode == 2) // transfer
        return in[31:25] == out[31:25];
    else if (opCode == 6) // stop
        return in[31:28] == out[31:28];
    else
        return in == out;
endfunction

module mkFuzzInstructionConversion(Test);
    Randomize#(Bit#(32)) randomizer <- mkGenericRandomizer();
    Reg#(Bit#(32)) rawIns <- mkRegU;
    Reg#(DMAInstruction) ins <- mkRegU;
    Reg#(UInt#(32)) failCount <- mkReg(0);
    Reg#(UInt#(33)) count <- mkRegU;

    method String testName = "Test Fuzzing DMA Instruction encode/decode";

    method Stmt runTest = seq
        randomizer.cntrl.init();
        for (count <= 0; count < 1_000_000; count <= count + 1) seq
            action
                let val <- randomizer.next();
                rawIns <= val;
                ins <= unpack(val);
            endaction
            if (!functionallyEquivalent(rawIns, pack(ins))) action
                /*$display("%h %h", rawIns, pack(ins));*/
                /*$display(fshow(ins));*/
                failCount <= failCount + 1;
            endaction
        endseq
        /*$display(failCount);*/
        testAssert(failCount == 0);
    endseq;

endmodule


function CheriMemRequest64 simpleWrite64(Bit#(40) addr, Bit#(64) data);
    return MemoryRequest {
        addr:          unpack(addr),
        masterID:      0,
        transactionID: 0,
        operation: tagged Write {
            uncached:    True,
            conditional: False,
            byteEnable:  unpack('h0000_0000_0000_00FF),
            data:        Data { data: zeroExtend(data) },
            last:        True
        }
    };
endfunction

function CheriMemRequest64 configWrite(Bit#(32) data);
    return MemoryRequest {
        addr:           unpack('h4),
        masterID:       0,
        transactionID:  0,
        operation:      tagged Write {
            uncached:       True,
            conditional:    False,
            byteEnable:     unpack('hF << 4),
            data:           Data { data: zeroExtend(reverseBytes(data)) << 32 },
            last:           True
        }
    };
endfunction

DMAConfiguration testDMAConf = DMAConfiguration {
    icacheID:   0,
    readID:     1,
    writeID:    2,
    useTLB:     False
};

module mkTestRegistersSetCorrectly
        #(DMA#(256) dut, Integer virtualInterface)(Test);
    Reg#(Error) lastError <- mkRegU;

    let uintVirtualInterface = fromInteger(virtualInterface);
    Bit#(40) ifcOffset = fromInteger(virtualInterface) * 4 * 1024;

    method String testName = "Test DMA interface " +
       integerToString(virtualInterface) + " values are set correctly";

    method runTest = seq
        dut.configuration.request.put(
            simpleWrite64(ifcOffset + 'h8, reverseBytes('h67_89AB_CDEF)));
        action
            let resp <- dut.configuration.response.get();
            lastError <= resp.error;
        endaction
        testAssertEqual(NoError, lastError);
        testAssertEqual('h67_89AB_CDEF,
            dut.debug.readExternalProgramCounter(uintVirtualInterface));

        dut.configuration.request.put(
            simpleWrite64(ifcOffset + 'h10, reverseBytes('h98_7654_3210)));
        action
            let resp <- dut.configuration.response.get();
            lastError <= resp.error;
        endaction
        testAssertEqual(NoError, lastError);
        testAssertEqual('h98_7654_3210,
            dut.debug.readExternalSource(uintVirtualInterface));

        dut.configuration.request.put(
            simpleWrite64(ifcOffset + 'h18, reverseBytes('hDC_5678_BA98)));
        action
            let resp <- dut.configuration.response.get();
            lastError <= resp.error;
        endaction
        testAssertEqual(NoError, lastError);
        testAssertEqual('hDC_5678_BA98,
            dut.debug.readExternalDestination(uintVirtualInterface));
    endseq;

endmodule

module mkTestDifferentPCsForDifferentThreads#(DMA#(256) dut)(Test);
    Reg#(UInt#(64)) pcOne <- mkRegU;
    Reg#(UInt#(64)) pcTwo <- mkRegU;

    method String testName = "Test different PCs for different DMA threads";

    method runTest = seq
        dut.configuration.request.put(
            simpleWrite64(8, reverseBytes('hA1B2_C3D4_E4)));
        action
            let _ <- dut.configuration.response.get();
        endaction

        dut.configuration.request.put(
            simpleWrite64(255 * 4 * 1024 + 8, reverseBytes('hDEAD_BEEF_12)));
        action
            let _ <- dut.configuration.response.get();
        endaction

        action
            pcOne <= dut.debug.readExternalProgramCounter(0);
        endaction
        action
            pcTwo <= dut.debug.readExternalProgramCounter2(255);
        endaction

        testAssertEqual('hA1B2_C3D4_E4, pcOne);
        testAssertEqual('hDEAD_BEEF_12, pcTwo);
    endseq;
endmodule

module mkTestSignalsSetCorrectly#(DMA#(1) dut)(Test);

    function Action resetSignals() = action
        dut.debug.startTransaction <= tagged Invalid;
        /*dut.debug.enableInterrupt <= tagged Invalid;*/
    endaction;

    function Action dropResponse() = action
        let _ <- dut.configuration.response.get();
    endaction;


    method String testName =
        "Test start and enable irq signals are set correctly";

    method runTest = seq
        testAssertEqual(tagged Invalid, dut.debug.startTransaction._read());
        /*testAssertEqual(tagged Invalid, dut.debug.enableInterrupt._read());*/

        dut.configuration.request.put(configWrite('h3));
        dropResponse();
        testAssertEqual(tagged Valid True, dut.debug.startTransaction._read());
        /*testAssertEqual(tagged Valid True, dut.debug.enableInterrupt._read());*/

        resetSignals();
        dut.configuration.request.put(configWrite('h1));
        dropResponse();
        testAssertEqual(tagged Valid True, dut.debug.startTransaction._read());
        /*testAssertEqual(tagged Valid False, dut.debug.enableInterrupt._read());*/

        resetSignals();
        dut.configuration.request.put(configWrite('h2));
        dropResponse();
        testAssertEqual(tagged Valid False, dut.debug.startTransaction._read());
        /*testAssertEqual(tagged Valid True, dut.debug.enableInterrupt._read());*/
    endseq;

endmodule

typedef enum {
    TTRead, TTWrite, TTInvalid
} TransactionType deriving (Bits, Eq, FShow);

module mkTestRequestValuesAreMirroredCorrectly#(DMA#(1) dut)(Test);

    Reg#(CheriTransactionID)    lastTransactionID   <- mkRegU;
    Reg#(CheriMasterID)         lastMasterID        <- mkRegU;
    Reg#(TransactionType)       lastTransactionType <- mkRegU;

    function TransactionType typeOfResp(CheriMemResponse64 resp);
        case (resp.operation) matches
            tagged Read .*: return TTRead;
            tagged Write:   return TTWrite;
            default:        return TTInvalid;
        endcase
    endfunction

    method String testName =
        "Test DMA produces responses with correct form";

    method runTest = seq
        dut.configuration.request.put(MemoryRequest {
            addr:          unpack('h8),
            masterID:      'h1,
            transactionID: 'h4,
            operation:     tagged Write {
                uncached:       True,
                conditional:    False,
                byteEnable:     unpack('hFF),
                data:           Data { data: 0 },
                last:           True
            }
        });
        action
            let resp <- dut.configuration.response.get();
            lastMasterID        <= resp.masterID;
            lastTransactionID   <= resp.transactionID;
            lastTransactionType <= typeOfResp(resp);
        endaction
        testAssertEqual(1, lastMasterID);
        testAssertEqual(4, lastTransactionID);
        testAssertEqual(TTWrite, lastTransactionType);

        dut.configuration.request.put(MemoryRequest {
            addr:           unpack('h0),
            masterID:       'h0,
            transactionID:  'h7,
            operation:      tagged Read {
                uncached:       True,
                linked:         False,
                noOfFlits:      1,
                bytesPerFlit:   BYTE_32
            }
        });
        action
            let resp <- dut.configuration.response.get();
            lastMasterID        <= resp.masterID;
            lastTransactionID   <= resp.transactionID;
            lastTransactionType <= typeOfResp(resp);
        endaction
        testAssertEqual(0, lastMasterID);
        testAssertEqual(7, lastTransactionID);
        testAssertEqual(TTRead, lastTransactionType);

    endseq;

endmodule

CheriMemRequest64 readEngineReadyReq = MemoryRequest {
    addr:           unpack(0),
    masterID:       0,
    transactionID:  0,
    operation: tagged Read {
        uncached:       True,
        linked:         False,
        noOfFlits:      0,
        bytesPerFlit:   BYTE_4
    }
};

module mkTestCanReadEngineReady#(DMA#(1) dut)(Test);

    Reg#(Bool) invalidResponse <- mkReg(False);
    Reg#(Bool) engineReady <- mkRegU;

    function Action getResponse() = action
        let resp <- dut.configuration.response.get();
        case (resp.operation) matches
            tagged Read .data: begin
                Bit#(32) rawResp = truncate(data.data.data);
                Bit#(32) respData = reverseBytes(rawResp);
                engineReady <= unpack(respData[0]);
            end
            default:
                invalidResponse <= True;
        endcase
    endaction;


    method String testName = "Test that the engine ready bit can be read";

    method runTest = seq
        dut.configuration.request.put(readEngineReadyReq);
        getResponse();
        testAssert(!invalidResponse);
        testAssertEqual(engineReady, True);

        /*dut.debug.forceEngineReady(False);*/
        dut.configuration.request.put(readEngineReadyReq);
        getResponse();
        testAssert(!invalidResponse);
        testAssertEqual(engineReady, False);

        /*dut.debug.forceEngineReady(True);*/
        dut.configuration.request.put(readEngineReadyReq);
        getResponse();
        testAssert(!invalidResponse);
        testAssertEqual(engineReady, True);
    endseq;

endmodule


module mkTestErrorOnBadRequest(Test);

    method String testName =
        "Test DMA produces errors in response to silly requests";

    method runTest = seq
        //TODO: Test goes here.
    endseq;

endmodule

function CheriMemResponse simpleReadResponse(
        CheriMasterID masterID, Bit#(256) data) =
    MemoryResponse {
        masterID: masterID,
        transactionID: 0,
        error: NoError,
        operation: tagged Read {
            data: Data { data: data },
            last: True
        }
    };

Bit#(32) start_transaction  = 'h1;
Bit#(32) enable_irq         = 'h2;
Bit#(32) clear_irq          = 'h4;

function Stmt startTransfer(
        DMA#(threads) dma, Bit#(64) pc, Bit#(64) source, Bit#(64) dest);
    return startTransferCustom(dma, start_transaction, pc, source, dest);
endfunction

function Stmt startTransferCustom(
        DMA#(threads) dma, Bit#(32) confReg, Bit#(64) pc,
        Bit#(64) source, Bit#(64) dest);

    let dropConfigResp = (action
        let _ <- dma.configuration.response.get();
    endaction);

    return (seq
        /*$display("Starting transfer.");*/
        dma.configuration.request.put(simpleWrite64('h8, reverseBytes(pc)));
        /*$display("PC written.");*/
        dropConfigResp();
        /*$display("PC Resp dropped.");*/
        dma.configuration.request.put(simpleWrite64('h10, reverseBytes(source)));
        /*$display("Source written.");*/
        dropConfigResp();
        /*$display("Source resp dropped.");*/
        dma.configuration.request.put(simpleWrite64('h18, reverseBytes(dest)));
        /*$display("Dest written");*/
        dropConfigResp();
        /*$display("Dest resp dropped.");*/
        dma.configuration.request.put(configWrite(confReg));
        /*$display("Config written.");*/
        dropConfigResp();
        /*$display("Config resp dropped.");*/
    endseq);
endfunction

function ActionValue#(Bool) expectReadReq(
        DMA#(threads) dma, CheriMasterID expectedMasterID,
        Bit#(40) expectedAddr, BytesPerFlit bytesPerFlit);
    return (actionvalue
        let correct = True;
        let req <- dma.memory.request.get();
        correct = correct && (pack(req.addr) == expectedAddr);
        correct = correct && (req.masterID == expectedMasterID);
        case (req.operation) matches
            tagged Read .read: begin
                correct = correct && (read.noOfFlits == 0);
                correct = correct && (read.bytesPerFlit == bytesPerFlit);
            end
            default:
                correct = False;
        endcase
        if (!correct)
            $display("%t: ", $time, fshow(req));
        return correct;
    endactionvalue);
endfunction

function ActionValue#(Bool) expectWriteReq(
        DMA#(threads) dma, CheriMasterID expectedMasterID,
        Bit#(40) expectedAddr, Vector#(32, Bool) byteEnable, Bit#(256) data);
    return (actionvalue
        let correct = True;
        let req <- dma.memory.request.get();
        correct = correct && (pack(req.addr) == expectedAddr);
        correct = correct && (req.masterID == expectedMasterID); // write
        case (req.operation) matches
            tagged Write .write: begin
                correct = correct && (write.byteEnable == byteEnable);
                correct = correct && (write.data.data == data);
            end
            default:
                correct = False;
        endcase
        if (!correct)
            $display("%t: Got ", $time, fshow(req));
        return correct;
    endactionvalue);
endfunction


function Action avToRegister(Reg#(t) theReg, ActionValue#(t) get) = action
    let value <- get();
    theReg <= value;
endaction;

function Vector#(length, Bit#(32)) progToBigEndian(
        Vector#(length, DMAInstruction) prog);
    return map(compose(reverseBytes, pack), prog);
endfunction

function CheriMemResponse writeResp(CheriMasterID masterID) = MemoryResponse {
    masterID: masterID,
    transactionID: 0,
    error: NoError,
    operation: tagged Write
};

module mkTestMinimalProgram#(DMA#(1) dut)(Test);
    Reg#(Bool) reqCorrect <- mkReg(True);

    Vector#(2, DMAInstruction) prog;
    prog[0] = tagged Transfer { size: Bits256 };
    prog[1] = tagged Stop;

    method String testName = "Test DMA running a minimal program";

    method runTest = seq
        /*$display("About to start transfer.");*/

        startTransfer(dut, 0, 'h100, 'h200);

        /*$display("Read program.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 0, 0, BYTE_32));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(
            0, zeroExtend(pack(progToBigEndian(prog)))));

        /*$display("First read request");*/
        avToRegister(reqCorrect, expectReadReq(dut, 1, 'h100, BYTE_32));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(1, 'hABCD_1234));


        /*$display("First write request");*/
        avToRegister(reqCorrect,
            expectWriteReq(dut, 2, 'h200, unpack('1), 'hABCD_1234));
        testAssert(reqCorrect);
        dut.memory.response.put(writeResp(2));
    endseq;

endmodule

function Stmt writeReadyToReg(Reg#(Bool) engineReady, DMA#(threads) dma) = seq
    dma.configuration.request.put(readEngineReadyReq);
    action
        let resp <- dma.configuration.response.get();
        case (resp.operation) matches
            tagged Read .read: begin
                Bit#(32) rawResponse = truncate(read.data.data);
                engineReady <= unpack(reverseBytes(rawResponse)[0]);
            end
            default:
                dynamicAssert(False, "Bad config read response");
        endcase
    endaction
endseq;

module mkTestSimpleLoop(Test);
    let dut <- mkSingleThreadPhysicalDMA(DMAConfiguration {
        icacheID:00,
        readID:  01,
        writeID: 02,
        useTLB: False
    });
    Reg#(Bool) reqCorrect <- mkReg(True);
    Reg#(Bool) engineReady <- mkRegU;

    Vector#(32, Bool) allBE = unpack('1);

    Vector#(4, DMAInstruction) prog;
    prog[0] = tagged SetLoopReg { target: LoopReg0, value: 1 };
    prog[1] = tagged Transfer { size: Bits256 };
    prog[2] = tagged Loop { loopReg: LoopReg0, offset: 1 };
    prog[3] = tagged Stop;


    method String testName = "Test a simple loop program";
    // This is also approximately tests the engine ready bit.

    method runTest = seq
        startTransfer(dut, 'h1000, 'h2000, 'h3000);

        writeReadyToReg(engineReady, dut);
        testAssertEqual(False, engineReady);

        /*$display("Program.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 00, 'h1000, BYTE_32));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(
            00, zeroExtend(pack(progToBigEndian(prog)))));

        /*$display("First read.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 01, 'h2000, BYTE_32));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(01, 'hFEED_DEAD_DEED_BEEF));

        /*$display("First write.");*/
        avToRegister(reqCorrect,
            expectWriteReq(dut, 02, 'h3000, allBE, 'hFEED_DEAD_DEED_BEEF));
        testAssert(reqCorrect);
        dut.memory.response.put(writeResp(02));

        /*$display("Second read.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 01, 'h2020, BYTE_32));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(01, 'h1234_5678_8765_4321));

        /*$display("Second write");*/
        avToRegister(reqCorrect,
            expectWriteReq(dut, 02, 'h3020, allBE, 'h1234_5678_8765_4321));
        testAssert(reqCorrect);
        dut.memory.response.put(writeResp(02));

        /*$display("Checking ready.");*/
        writeReadyToReg(engineReady, dut);
        testAssertEqual(False, engineReady);
        // Not ready at first, as write transaction needs to clear.

        writeReadyToReg(engineReady, dut);
        testAssertEqual(True, engineReady);
        // Write transaction has cleared.

    endseq;

endmodule

module mkTestAdd#(DMA#(1) dut)(Test);
    Reg#(Bool) reqCorrect <- mkReg(True);

    Vector#(7, DMAInstruction) prog;
    prog[0] = tagged Add { target: Both, amount: 1 };
    prog[1] = tagged Transfer { size: Bits8 };
    prog[2] = tagged Add { target: SourceOnly, amount: 2 };
    prog[3] = tagged Transfer { size: Bits8 };
    prog[4] = tagged Add { target: DestOnly, amount: 3 };
    prog[5] = tagged Transfer { size: Bits8 };
    prog[6] = tagged Stop;

    method String testName = "Test a program using the add instruction.";
    // Also tests using single byte transfers

    method runTest = seq
        /*$display("Starting.");*/
        startTransfer(dut, 'h1000, 'h2000, 'h3000);

        /*$display("OK. Expecting program read.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 0, 'h1000, BYTE_32));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(0,
            zeroExtend(pack(progToBigEndian(prog)))));

        /*$display("OK. Expecting source read 2001.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 1, 'h2001, BYTE_1));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(1, 'hA1 << 8));

        // Naturally read should be 'h2002, then add 2 to get 'h2004
        // Write should be at 'h3002, per default
        /*$display("OK. Expecting read req at 2004.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 1, 'h2004, BYTE_1));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(1, 'hB2 << 32));

        /*$display("OK. Expecting write req at 3001");*/
        avToRegister(reqCorrect,
            expectWriteReq(dut, 2, 'h3001, unpack(1 << 1), 'hA1 << 8));
        testAssert(reqCorrect);
        dut.memory.response.put(writeResp(2));

        // Some ordering weirdness. I would expect the write to come
        // next, but for some reason it doesn't.
        /*$display("OK. Expecting read req at 2005.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 1, 'h2005, BYTE_1));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(1, 'hC3 << 40));

        /*$display("OK. Expecting write req at 3002.");*/
        avToRegister(reqCorrect,
            expectWriteReq(dut, 2, 'h3002, unpack(1 << 2), 'hB2 << 16));
        testAssert(reqCorrect);
        dut.memory.response.put(writeResp(2));

        /*$display("OK. Expecting write req at 3006.");*/
        avToRegister(reqCorrect,
            expectWriteReq(dut, 2, 'h3006, unpack(1 << 6), 'hC3 << 48));
        testAssert(reqCorrect);
        dut.memory.response.put(writeResp(2));
    endseq;

endmodule

function Bit#(256) justStopProg();
    Vector#(1, DMAInstruction) prog = newVector();
    prog[0] = tagged Stop;
    return zeroExtend(pack(progToBigEndian(prog)));
endfunction

module mkTestNoIRQByDefault#(DMA#(1)dut)(Test);

    Reg#(Bool) reqCorrect <- mkRegU;
    Reg#(Bool) engineReady <- mkReg(False);

    method testName =
        "Test that completing a program doesn't normally cause IRQ";

    method runTest = seq
        startTransfer(dut, 0, 0, 0);
        avToRegister(reqCorrect, expectReadReq(dut, 0, 0, BYTE_32));
        dut.memory.response.put(simpleReadResponse(0, justStopProg()));

        while(!engineReady)
            writeReadyToReg(engineReady, dut);

        testAssertEqual(False, dut.getIRQ());
    endseq;
endmodule

module mkTestCanEnableIRQ#(DMA#(1)dut)(Test);

    Reg#(Bool) reqCorrect <- mkRegU;
    Reg#(Bool) engineReady <- mkReg(False);

    method testName =
        "Test that interrupt-on-completion can be enabled";

    method runTest = seq
        startTransfer(dut, 0, 0, 0);
        avToRegister(reqCorrect, expectReadReq(dut, 0, 0, BYTE_32));
        dut.memory.response.put(simpleReadResponse(0, justStopProg()));

        dut.configuration.request.put(configWrite('h2)); // enable interrupt
        action
            let _ <- dut.configuration.response.get();
        endaction

        while (!engineReady)
            writeReadyToReg(engineReady, dut);

        testAssertEqual(True, dut.getIRQ());
    endseq;
endmodule

module mkTestCanClearIRQ#(DMA#(1)dut)(Test);

    Reg#(Bool) reqCorrect <- mkRegU;
    Reg#(Bool) engineReady <- mkReg(False);

    method testName =
        "Test that a fired IRQ can be cleared";

    method runTest = seq
        startTransfer(dut, 0, 0, 0);
        avToRegister(reqCorrect, expectReadReq(dut, 0, 0, BYTE_32));
        dut.memory.response.put(simpleReadResponse(0, justStopProg()));

        dut.configuration.request.put(configWrite('h2)); // enable interrupt
        action
            let _ <- dut.configuration.response.get();
        endaction

        while (!engineReady)
            writeReadyToReg(engineReady, dut);

        testAssertEqual(True, dut.getIRQ());

        dut.configuration.request.put(configWrite('h4)); // clear interrupt
        action
            let _ <- dut.configuration.response.get();
        endaction

        testAssertEqual(False, dut.getIRQ());
    endseq;
endmodule

module mkTestIRQBoundToTransaction#(DMA#(1)dut)(Test);

    Reg#(Bool) reqCorrect <- mkRegU;
    Reg#(Bool) engineReady <- mkReg(False);

    method String testName =
        "Test that enabling IRQ for one transaction doesn't for the next.";

    method runTest = seq
        /*$display("Start transaction.");*/
        startTransferCustom(dut, start_transaction | enable_irq, 0, 0, 0);
        /*$display("Expect read req.");*/
        avToRegister(reqCorrect, expectReadReq(dut, 0, 0, BYTE_32));
        /*$display("Returning prog");*/
        dut.memory.response.put(simpleReadResponse(0, justStopProg()));

        /*$display("Waiting for completion");*/
        while (!engineReady)
            writeReadyToReg(engineReady, dut);

        engineReady <= False;

        testAssertEqual(True, dut.getIRQ());

        dut.configuration.request.put(
            configWrite(clear_irq | start_transaction));
        action
            let _ <- dut.configuration.response.get();
        endaction

        while (!engineReady)
            writeReadyToReg(engineReady, dut);

        testAssertEqual(False, dut.getIRQ());
    endseq;

endmodule

module mkTestCanEnableAndDisableIRQInOneReq#(DMA#(1) dut)(Test);

    Reg#(Bool) reqCorrect <- mkRegU;
    Reg#(Bool) engineReady <- mkReg(False);

    Vector#(8, DMAInstruction) nopProg = newVector();
    nopProg[0] = tagged SetLoopReg { target: LoopReg0, value: 0 };
    nopProg[1] = tagged SetLoopReg { target: LoopReg0, value: 0 };
    nopProg[2] = tagged SetLoopReg { target: LoopReg0, value: 0 };
    nopProg[4] = tagged SetLoopReg { target: LoopReg0, value: 0 };
    nopProg[4] = tagged SetLoopReg { target: LoopReg0, value: 0 };
    nopProg[5] = tagged SetLoopReg { target: LoopReg0, value: 0 };
    nopProg[6] = tagged Stop; // Otherwise attempts next instruction
    nopProg[7] = tagged Stop; // And jams. I am lazy.

    let dropConfigResp = (action
        let _ <- dut.configuration.response.get();
    endaction);

    method String testName =
        "Test that one memory request can clear last IRQ, and enable next.";

    method runTest = seq
        /*$display("Start first transfer");*/
        startTransferCustom(dut, start_transaction | enable_irq, 0, 0, 0);
        /*$display("Read program request");*/
        avToRegister(reqCorrect, expectReadReq(dut, 0, 0, BYTE_32));
        /*$display("Returning stop program");*/
        dut.memory.response.put(simpleReadResponse(0, justStopProg()));

        /*$display("Waiting for engine to become ready.");*/
        while (!engineReady)
            writeReadyToReg(engineReady, dut);

        engineReady <= False;

        /*$display("Confirming IRQ raised");*/
        testAssertEqual(True, dut.getIRQ());
        /*$display("Setting new PC");*/
        dut.configuration.request.put(simpleWrite64('h8, reverseBytes('h20)));
        dropConfigResp();
        /*$display("Starting new transaction");*/
        dut.configuration.request.put(
            configWrite(clear_irq | start_transaction | enable_irq));
        dropConfigResp();
        avToRegister(reqCorrect, expectReadReq(dut, 0, 'h20, BYTE_32));
        /*$display("Returning long nop program.");*/
        dut.memory.response.put(
            simpleReadResponse(0, pack(progToBigEndian(nopProg))));

        testAssertEqual(False, dut.getIRQ());

        /*$display("Waiting for program to finish");*/
        while (!engineReady)
            writeReadyToReg(engineReady, dut);

        testAssertEqual(True, dut.getIRQ());

        /*$display("Do a clear_irq write");*/
        dut.configuration.request.put(configWrite(clear_irq));
        dropConfigResp();

        testAssertEqual(False, dut.getIRQ());
    endseq;
endmodule

module mkTestTLBUse#(DMA#(1) dut)(Test);

    Reg#(Bool) reqCorrect <- mkRegU;

    Vector#(2, DMAInstruction) prog = newVector();
    prog[0] = tagged Transfer { size: Bits64 };
    prog[1] = tagged Stop;

    function Action expectTLBRequest(Client#(TlbRequest, TlbResponse) tlb,
            MIPS::Address address, Bool write) = action
        let req <- tlb.request.get();
        reqCorrect <= (address == req.addr && req.write == write);
    endaction;

    method String testName = "Test use of the TLB";

    method runTest = seq
        /*$display("Starting Transfer");*/
        startTransfer(dut, 'h1000, 'h2000, 'h3000);

        /*$display("PC TLB request");*/
        expectTLBRequest(dut.instructionTLBClient, 'h1000, False);
        testAssert(reqCorrect);
        dut.instructionTLBClient.response.put(TlbResponse { addr: 'h4000 });

        /*$display("Reading program");*/
        avToRegister(reqCorrect, expectReadReq(dut, 0, 'h4000, BYTE_32));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(
            0, zeroExtend(pack(progToBigEndian(prog)))));

        expectTLBRequest(dut.dataTLBClient, 'h2000, False);
        testAssert(reqCorrect);
        dut.dataTLBClient.response.put(TlbResponse { addr: 'h5000, write: False });

        avToRegister(reqCorrect, expectReadReq(dut, 1, 'h5000, BYTE_8));
        testAssert(reqCorrect);
        dut.memory.response.put(simpleReadResponse(1, 'hDEED));

        expectTLBRequest(dut.dataTLBClient, 'h3000, True);
        testAssert(reqCorrect);
        dut.dataTLBClient.response.put(TlbResponse { addr: 'h6000, write: True });

        avToRegister(reqCorrect, expectWriteReq(dut, 2, 'h6000, unpack('hFF), unpack('hDEED)));
        testAssert(reqCorrect);
    endseq;

endmodule

module mkDumpExampleInstructions(Test);
    method testName = "Easiest way to get data out of bluespec";

    method runTest = seq
        $displayh(pack(tagged SetLoopReg { target: LoopReg1, value: 'hBEEF }));
        $displayh(pack(tagged Loop { loopReg: LoopReg3, offset: 4 }));
        $displayh(pack(tagged Transfer { size: Bits256 }));
        /*$displayh(pack(tagged Add { target: DestOnly, amount: 'h100 }));*/
        /*$displayh(pack(tagged Sub { target: SourceOnly, amount: 'hBEDE }));*/
        $displayh(pack(tagged Stop));
    endseq;
endmodule

module mkActionAsTest#(Action act)(Test);
    method testName = "Dummy Test";
    method runTest = seq
        act;
    endseq;
endmodule

(* synthesize *)
module mkDMA256#(DMAConfiguration conf)(DMA#(256));
    DMA#(256) dma <- mkDMA(conf);
    return dma;
endmodule

module mkTestDMA(Empty);
    Clock clk <- exposeCurrentClock;
    MakeResetIfc rst <- mkReset(1, True, clk);

    let virtDMAConf = DMAConfiguration {
        icacheID:   0,
        readID:     1,
        writeID:    2,
        useTLB:     True
    };

    DMA#(256) dmaMt1 <- mkDMA256(testDMAConf, reset_by rst.new_rst);
    /*// Need another due to port collision*/
    DMA#(256) dmaMt2 <- mkDMA256(testDMAConf, reset_by rst.new_rst);
    DMA#(1)   dmaSt <-
        mkSingleThreadPhysicalDMA(testDMAConf, reset_by rst.new_rst);
    DMA#(1)   dmaVirtSt <-
        mkSingleThreadPhysicalDMA(virtDMAConf, reset_by rst.new_rst);

    Test fuzzInstructionConversion <- mkFuzzInstructionConversion();
    Test lowRegistersSetCorrectly <- mkTestRegistersSetCorrectly(dmaMt1, 0);
    Test highRegistersSetCorrectly <- mkTestRegistersSetCorrectly(dmaMt2, 255);
    Test differentInterfaces <- mkTestDifferentPCsForDifferentThreads(dmaMt1);
    Test testMirroring <- mkTestRequestValuesAreMirroredCorrectly(dmaSt);
    Test testMinimalProgram <- mkTestMinimalProgram(dmaSt);
    Test testSimpleLoop <- mkTestSimpleLoop();
    Test testAdd <- mkTestAdd(dmaSt);
    Test testNoIRQ <- mkTestNoIRQByDefault(dmaSt);
    Test testEnableIRQ <- mkTestCanEnableIRQ(dmaSt);
    Test testClearIRQ <- mkTestCanClearIRQ(dmaSt);
    Test testIRQBound <- mkTestIRQBoundToTransaction(dmaSt);
    Test testReenable <- mkTestCanEnableAndDisableIRQInOneReq(dmaSt);
    Test testTLBUse <- mkTestTLBUse(dmaVirtSt);

    // Test signals starts off with an invalid request, and promptly falls over.
    /*Test testEngineReady <- mkTestCanReadEngineReady();*/
    /*Test testSignals <- mkTestSignalsSetCorrectly();*/

    runTestsWithBookeeping(noAction, rst.assertReset, list(
        fuzzInstructionConversion,
        lowRegistersSetCorrectly,
        highRegistersSetCorrectly,
        differentInterfaces,
        testMirroring,
        testMinimalProgram,
        testSimpleLoop,
        testAdd,
        testNoIRQ,
        testEnableIRQ,
        testClearIRQ,
        testIRQBound,
        testReenable,
        testTLBUse
    ));
endmodule
