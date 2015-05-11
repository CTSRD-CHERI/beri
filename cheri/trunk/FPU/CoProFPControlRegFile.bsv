/*-
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Colin Rothwell as part of his final year
 * undergraduate project.
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
import CoProFPTypes :: *;
import MIPS :: *;

interface CoProFPControlRegFile;
    method Action upd(RegNum addr, MIPSReg d);
    method MIPSReg sub(RegNum addr);
endinterface

module mkCoProFPControlRegFile(CoProFPControlRegFile);
    Reg#(FCSR) fcsr <- mkReg(unpack(0));

    FIR fir = FIR { f64: True, 
                    l: False, w: False,
                    threeD: False,
                    ps: True, d: True, s: True,
                    pid: 0, rev: 0 };

    method Action upd(RegNum addr, MIPSReg d);
        let fcsr_tmp = fcsr;
	    case (addr)
		    25:	begin
                fcsr_tmp.fcc = unpack(d[7:0]);
            end
		    26:	begin
                fcsr_tmp.cause = unpack(d[17:12]);
                fcsr_tmp.flags = unpack(d[6:2]);
            end
		    28: begin
                fcsr_tmp.enables = unpack(d[11:7]);
                fcsr_tmp.flushToZero = unpack(d[2]);
                fcsr_tmp.roundingMode = unpack(d[1:0]);
            end
            31: fcsr_tmp = unpack(d);
        endcase
	    fcsr <= fcsr_tmp;
	endmethod
    
    method MIPSReg sub(RegNum addr);
	    case (addr)
                0: return pack(fir);
                25: return {
                    32'b0, 24'b0, 
                    pack(fcsr.fcc)
                };
                26: return {
                    32'b0, 14'b0, 
                    pack(fcsr.cause), 
                    5'b0, 
                    pack(fcsr.flags),
                    2'b0
                };
                28: return {
                    32'b0, 20'b0, 
                    pack(fcsr.enables),
                    4'b0,
                    pack(fcsr.flushToZero),
                    pack(fcsr.roundingMode)
                };
                31: return pack(fcsr);
	    endcase
	endmethod
endmodule
