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
package CoProFPInst;

import CoProFPTypes :: *;
import MIPS :: *;

typeclass TCoProInst#(type custom_schema);
	function custom_schema convert(CoProInst inst);
endtypeclass

instance TCoProInst#(FPRType);
	function FPRType convert(CoProInst inst);
		FPRType result = unpack(0);
		result.fmt = unpack(pack(inst.op));
		result.ft = inst.regNumDest;
		result.fs = inst.regNumA;
		result.fd = inst.regNumB;
		result.func = unpack(pack(inst.imm));
		return result;
	endfunction
endinstance
	
instance TCoProInst#(FPRIType);
	function FPRIType convert(CoProInst inst);
		let result = unpack(0);
		result.sub = unpack(pack(inst.op));
		result.rt = inst.regNumDest;
		result.fs = inst.regNumA;
		return result;
	endfunction
endinstance

instance TCoProInst#(FPBType);
	function FPBType convert(CoProInst inst);
		FPBType result = unpack(0);
		result.cc = inst.regNumDest[4:2];
		result.nd = unpack(inst.regNumDest[1]);
		result.tf = unpack(inst.regNumDest[0]);
		result.offset = { pack(inst.regNumA), pack(inst.regNumB), pack(inst.imm) };
		return result;
	endfunction
endinstance

instance TCoProInst#(FPCType);
	function FPCType convert(CoProInst inst);
		FPCType result = unpack(0);
		result.fmt = unpack(pack(inst.op));
		result.ft = inst.regNumDest;
		result.fs = inst.regNumA;
		result.cc = pack(inst.regNumB)[4:2];
		result.func = unpack(pack(inst.imm));
		return result;
	endfunction
endinstance

instance TCoProInst#(FPRMCType);
	function FPRMCType convert(CoProInst inst);
		FPRMCType result = unpack(0);
		result.fmt = unpack(pack(inst.op));
		result.cc = pack(inst.regNumDest)[4:2];
		result.tf = unpack(pack(inst.regNumDest)[0]);
		result.fs = inst.regNumA;
		result.fd = inst.regNumB;
		return result;
	endfunction
endinstance

instance TCoProInst#(FPMemInstruction);
    function FPMemInstruction convert(CoProInst inst);
        FPMemInstruction result = unpack(0);
        case (inst.mipsOp)
            LWC1, LDC1: begin
                result.op = Load;
                result.loadTarget = inst.regNumDest;
            end
            SWC1, SDC1: begin
                result.op = Store;
                result.storeSource = FT;
                result.storeReg = inst.regNumDest;
            end
            COP3: begin
                CoProFPXOp fpxOp = unpack(pack(inst.imm)); // It just is. Don't argue.
                case (fpxOp)
                    LWXC1, LDXC1: result.op = Load;
                    SWXC1, SDXC1: result.op = Store;
                endcase
                result.loadTarget = inst.regNumB;
                result.storeSource = FS;
                result.storeReg = inst.regNumA;
            end
        endcase
        return result;
    endfunction
endinstance

endpackage
