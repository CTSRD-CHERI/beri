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
import FloatingPoint::*;

// Zero extend a quantity by padding on the LSB side.
function Bit#(m) zeroExtendLSB(Bit#(n) value)
    provisos(Add#(a__, n, m));

    Bit#(m) resp = 0;
    resp[valueOf(m)-1:valueOf(m)-valueOf(n)] = value;
    return resp;
endfunction

function Bit#(m) truncateLSB(Bit#(n) value);
    return value[valueOf(n)-1:valueOf(n)-valueOf(m)];
endfunction

function Double floatToDouble(Float in);
    if (isZero(in))
        return zero(in.sign);
    else if (isNaN(in)) 
        return qnan();
    else if (isInfinity(in))
        return infinity(in.sign);
    else begin
        let resp = Double { sign: in.sign, exp: ?, sfd: zeroExtendLSB(in.sfd)};
        resp.exp = zeroExtend(in.exp) + 896; // undo biasing
        return resp;
    end
endfunction

function Float doubleToFloat(Double in);
    if (isZero(in))
        return zero(in.sign);
    else if (isNaN(in)) 
        return qnan();
    else if (isInfinity(in))
        return infinity(in.sign);
    else begin
        Float resp = Float { sign: in.sign, exp: ?, sfd: ? };
        resp.sfd = truncateLSB(in.sfd);
        resp.exp = truncate(in.exp - 896);
        // Round up if more than half way between, or half way between, and
        // significand is odd
        if (in.sfd[28] == 1 && (in.sfd[27:0] != 0 || in.sfd[29] == 1))
            resp = unpack((pack(resp) + 1)[31:0]);
        return resp;
    end
endfunction

