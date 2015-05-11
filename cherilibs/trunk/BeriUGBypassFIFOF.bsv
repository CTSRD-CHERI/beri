/*-
 * Copyright (c) 2014 Simon W. Moore
 * Copyright (c) 2014 Alexandre Joannou
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
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

/******************************************************************************
 * Provides an unguarded bypass FIFOF with generic FIFOF interface
 ******************************************************************************/

package BeriUGBypassFIFOF;

import FIFOF::*;

module mkBeriUGBypassFIFOF(FIFOF#(a))
  provisos (Bits#(a, awidth));

  Wire#(Maybe#(a))   data_in    <- mkDWire(tagged Invalid);
  Wire#(a)           bypass_out <- mkDWire(?);
  PulseWire          do_deq     <- mkPulseWire;
  PulseWire          do_clear   <- mkPulseWire;

  Reg#(Maybe#(a))    data_buf   <- mkReg(tagged Invalid);
  
  Bool full = isValid(data_buf);
  Bool do_enq = isValid(data_in);
  Bool data_available = full || (!full && do_enq);

  rule update_buf (do_enq && !full && !do_deq && !do_clear);
    data_buf <= data_in;
  endrule

  rule inval_buf ((!do_enq && full && do_deq) || do_clear);
    data_buf <= tagged Invalid;
  endrule

  rule write_bypass;
    bypass_out <= fromMaybe(?, data_in);
  endrule

  rule assert_no_latched (do_enq && full);
    $display("Warning - BeriUGBypassFIFOF %0x value dropped", fromMaybe(?, data_in));
  endrule
  
  method Bool notEmpty = data_available;
  method Bool notFull  = !isValid(data_buf);
  method Action enq(a d);
    data_in <= tagged Valid d;
  endmethod
  method Action deq;
    do_deq.send();
  endmethod
  method a first = (data_buf matches tagged Valid .d
                    ?   d
                    :   bypass_out);
  method Action clear;
    do_clear.send;
  endmethod
  
endmodule  

endpackage: BeriUGBypassFIFOF
