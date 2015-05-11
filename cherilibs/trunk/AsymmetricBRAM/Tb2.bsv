/*-
 * Copyright (c) 2013 Alexandre Joannou
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


import StmtFSM::*;
import AsymmetricBRAM::*;
import BRAM::*;

(* synthesize *)
module mkTb2();
    AsymmetricBRAM#(Bit#(2),Bit#(32),Bit#(1),Bit#(64))   bram1 <- mkAsymmetricBRAM(False, False);
    AsymmetricBRAM#(Bit#(4),Bit#(32),Bit#(1),Bit#(256))  bram2 <- mkAsymmetricBRAM(False, False);
    AsymmetricBRAM#(Bit#(3),Bit#(8),Bit#(1),Bit#(32))    bram3 <- mkAsymmetricBRAM(False, False);
    AsymmetricBRAM#(Bit#(2),Bit#(8),Bit#(2),Bit#(8))     bram4 <- mkAsymmetricBRAM(False, False);

    Stmt test_bram1 = seq
        noAction;
        action
        $display("bram1.write(0,64'h0123456789abcdef)");
        bram1.write(0,64'h0123456789abcdef);
        endaction
        action
        $display("bram1.read(0)");
        bram1.read(0);
        endaction
        action
        $display("bram1.getRead(), should be 0x89abcdef");
        $display("addr 0 = 0x%0x", bram1.getRead());
        endaction
        action
        $display("bram1.read(1)");
        bram1.read(1);
        endaction
        action
        $display("bram1.getRead(), should be 0x01234567");
        $display("addr 1 = 0x%0x", bram1.getRead());
        endaction
        action
        $display("bram1.write(1,64'hfeedbabedeadbabe)");
        bram1.write(1,64'hfeedbabedeadbabe);
        endaction
        action
        $display("bram1.read(3)");
        bram1.read(3);
        endaction
        action
        $display("bram1.getRead(), should be 0xfeedbabe");
        $display("addr 3 = 0x%0x", bram1.getRead());
        endaction
        $display("TEST bram1 FINISHED");
    endseq;

    Stmt test_bram2 = seq
        noAction;
        action
        $display("bram2.write(0,256'h0123456789abcdeffeedbeefdeadbabe)");
        bram2.write(0,256'h0123456789abcdeffeedbeefdeadbabe);
        endaction
        action
        $display("bram2.read(0)");
        bram2.read(0);
        endaction
        action
        $display("bram2.getRead(), should be 0xdeadbabe");
        $display("addr 0 = 0x%0x", bram2.getRead());
        endaction
        action
        $display("bram2.read(2)");
        bram2.read(2);
        endaction
        action
        $display("bram2.getRead(), should be 0x89abcdef");
        $display("addr 2 = 0x%0x", bram2.getRead());
        endaction
        action
        $display("bram2.write(1,256'hfeedbabedeadbabe0123456789abcdef)");
        bram2.write(1,256'hfeedbabedeadbabe0123456789abcdef);
        endaction
        action
        $display("bram2.read(11)");
        bram2.read(11);
        endaction
        action
        $display("bram2.getRead(), should be 0xfeedbabe");
        $display("addr 11 = 0x%0x", bram2.getRead());
        endaction
        $display("TEST bram2 FINISHED");
    endseq;

    Stmt test_bram3 = seq
        noAction;
        action
        $display("bram3.write(0,32'hdeadbabe)");
        bram3.write(0,32'hdeadbabe);
        endaction
        action
        $display("bram3.read(0)");
        bram3.read(0);
        endaction
        action
        $display("bram3.getRead(), should be 0xbe");
        $display("addr 0 = 0x%0x", bram3.getRead());
        endaction
        action
        $display("bram3.read(1)");
        bram3.read(1);
        endaction
        action
        $display("bram3.getRead(), should be 0xba");
        $display("addr 1 = 0x%0x", bram3.getRead());
        endaction
        action
        $display("bram3.write(1,32'hfeeddead)");
        bram3.write(1,32'hfeeddead);
        endaction
        action
        $display("bram3.read(5)");
        bram3.read(5);
        endaction
        action
        $display("bram3.getRead(), should be 0xde");
        $display("addr 5 = 0x%0x", bram3.getRead());
        endaction
        $display("TEST bram3 FINISHED");
    endseq;

    Stmt test_bram4 = seq
        noAction;
        action
        $display("bram4.write(0,8'hab)");
        bram4.write(0,8'hab);
        endaction
        action
        $display("bram4.read(0)");
        bram4.read(0);
        endaction
        action
        $display("bram4.getRead(), should be 0xab");
        $display("addr 0 = 0x%0x", bram4.getRead());
        endaction
        action
        $display("bram4.read(1)");
        bram4.read(1);
        endaction
        action
        $display("bram4.getRead(), should be ??");
        $display("addr 1 = 0x%0x", bram4.getRead());
        endaction
        action
        $display("bram4.write(2,8'hcd)");
        bram4.write(2,8'hcd);
        endaction
        action
        $display("bram4.read(2)");
        bram4.read(2);
        endaction
        action
        $display("bram4.getRead(), should be 0xcd");
        $display("addr 2 = 0x%0x", bram4.getRead());
        endaction
        $display("TEST bram4 FINISHED");
    endseq;

    mkAutoFSM(test_bram1);
    mkAutoFSM(test_bram2);
    mkAutoFSM(test_bram3);
    mkAutoFSM(test_bram4);

endmodule
