/*-
 * Copyright (c) 2013 Ben Thorner
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Ben Thorner as part of his summer internship
 * and Colin Rothwell as part of his final year undergraduate project.
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

package CoProFP;

import MIPS::*;
import CoProFPTypes::*;
import CoProFPControlRegFile::*;
import CoProFPExecute::*;
import CoProFPInst::*;
import CoProFPDecode::*;
import CoProFPRegState::*;
import PopFIFO::*;

import RegFile::*;
import ClientServer::*;
import GetPut::*; 
import FIFO::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;

(* synthesize, options = "-aggressive-conditions" *)
module mkCoProFP(CoProIfc);
    Vector#(32, RegState) regStates <- replicateM(mkRegState);
    RegFile#(RegNum, MIPSReg) rf <- mkRegFileFull;

    RegState fcsrState <- mkRegState;
    CoProFPControlRegFile crf <- mkCoProFPControlRegFile;
  
    // The gateway is for holding instructions with blocked registers. 
    // If the FIFO is full, then there is an instruction waiting, and
    // putCoProInst will not be scheduled.
    FIFO#(CoProInst) gateway <- mkFIFO; 
    FIFO#(CoProFPToken) tokensForGet <- mkSizedFIFO(2);
    FIFO#(CoProFPToken) tokensForWbMethod <- mkSizedFIFO(4);
    // Can't be a bypass, or the load means it fails timing
    FIFO#(WritebackToken) tokensForWbRule <- mkSizedFIFO(4);

    let exec <- mkCoProFPExecute;

    rule decideAccess;
        let coProInst = gateway.first();
        let fpuInst = getCoProFPInst(coProInst);
        if (operandsAvailable(fpuInst, regStates, fcsrState.isFree())) begin
            FPRType rtype = convert(coProInst);
            let opS = rf.sub(rtype.fs);
            let opT = rf.sub(rtype.ft);
            let opD = rf.sub(rtype.fd);
            let controlS = crf.sub(rtype.fs);
            FCSR fcsr = unpack(crf.sub(31));

            let tok = getFPUToken(fpuInst, fcsr, opS, opT, opD, controlS);

            // If we put an instruction in where its destination reg is already
            // going to be written, then that destination reg will be unblocked
            // too early by the instruction already in the pipeline, so we don't
            // let it through. This is valid because no instruction can write to
            // both the FCSR and a register.
            Bool execute = True;
            if (blockedFCSR(tok))
                if (fcsrState.isFree()) begin
                    fcsrState.setBlocked();
                end else
                    execute = False;

            case (blockedRegister(tok)) matches
                tagged Valid .regNum: 
                    if (regStates[regNum].isFree())
                        regStates[regNum].setBlocked();
                    else             
                        execute = False;
            endcase

            if (execute) begin
                case (fpuExecuteRequest(fpuInst, opS, opT, fcsr.flushToZero)) matches
                    tagged Valid .req: exec.request.put(req);
                endcase

                gateway.deq();            
                tokensForGet.enq(tok);
            end
        end
    endrule

    function usesExecuteUnit(wbTok);
        Bool true = True; //Bluespec ignores return type, but can't workout what
        // type True is. Someone has defined it somewhere...
        case (wbTok.token.resultAction)
            GetFromExecuteUnit, GetExecuteCompare, GetExecuteComparePS:
                return true;
            default:
                return False;
        endcase
    endfunction

    function performWriteback(commit, tok, result);
        action
            debug($display("Actually performing writeback."));
            if (blockedFCSR(tok)) 
                fcsrState.setFree();

            case (blockedRegister(tok)) matches
                tagged Valid .regNum: begin
                    regStates[regNum].setFree();
                end
            endcase

            if (commit)
                case (tok.resultAction)
                    GetExecuteCompare, GetExecuteComparePS, ControlFromMain: begin
                        crf.upd(tok.targetReg, result);
                        trace($display("\tFP Control Reg %d <- %X", tok.targetReg, result));
                    end
                    ExecuteMOVZ, ExecuteMOVN, GetFromExecuteUnit, ExecuteFromMain,
                    WritebackFromMain, SimpleWriteback: begin
                        rf.upd(tok.targetReg, result);
                        trace($display("\tFP Reg %d <- %X", tok.targetReg, result));
                    end
                endcase
        endaction
    endfunction

    rule writeBackFromExecuteUnit (usesExecuteUnit(tokensForWbRule.first));
        let wbTok <- popFIFO(tokensForWbRule);
        let tok = wbTok.token;

        // Want to get result even if we don't commit, because otherwise the
        // next committing instruction will read it, and give the wrong result.
        MIPSReg result <- actionvalue
            case(tok.resultAction)
                GetFromExecuteUnit: begin
                    let res <- exec.response.get();
                    return res;
                end
                GetExecuteCompare, GetExecuteComparePS: begin
                    let res <- exec.response.get();
                    // fcc is the bit vector, cc in the indx into it.
                    let cc = tok.result[2:0];
                    let fcc = tok.fcsr.fcc;
                    if (tok.resultAction == GetExecuteComparePS)
                        fcc = updateFCC(fcc, cc, PS, res);
                    else
                        fcc = updateFCC(fcc, cc, S, res);
                    return zeroExtend(pack(fcc));
                end
            endcase
        endactionvalue;
        performWriteback(wbTok.commit, tok, result);
    endrule

    rule writebackRegular (!usesExecuteUnit(tokensForWbRule.first));
        let wbTok <- popFIFO(tokensForWbRule);
        performWriteback(wbTok.commit, wbTok.token, wbTok.token.result);
    endrule

    method Action putCoProInst(coProInst);
        debug($display("Receiving instruction in COP1"));
        gateway.enq(coProInst);
    endmethod
  
    method ActionValue#(CoProResponse) getCoProResponse(CoProVals coProVals);
        debug($display("Responding in COP1"));
        // Initialise response
    	let tok <- popFIFO(tokensForGet);
    	let response = CoProResponse { valid: False, data: ?, exception: None };
    	// Get result
        case (tok.resultAction)
            ControlFromMain, ExecuteFromMain:
                tok.result = coProVals.opA;
            ExecuteMOVZ:
                tok.result = (coProVals.opA == 0) ? tok.result : tok.otherOp;
            ExecuteMOVN: 
                tok.result = (coProVals.opA == 0) ? tok.otherOp : tok.result;
            RespondToGet: begin
                response.valid = True;
                response.data = tok.result;
            end
            InvalidInstruction: begin
                response.valid = True;
                response.exception = RI;
            end
        endcase
    
        tokensForWbMethod.enq(tok);

        return response;
    endmethod
   
    // This is a lie! We don't actually commit until we're in the rule, but the
    // MIPS pipeline can only have a few instructions in flight due to register
    // forwarding, so we defer actually writing back until the result is ready. 
    method Action commitWriteback(CoProWritebackRequest wbReq);	
        debug($display("Writeback called in COP1"));
        let tok <- popFIFO(tokensForWbMethod);
        tok.result = case (tok.resultAction)
            WritebackFromMain: wbReq.data;
            default: tok.result;
        endcase;
        let wbTok = WritebackToken { commit : wbReq.commit, token: tok };
        tokensForWbRule.enq(wbTok);
    endmethod
endmodule

endpackage
