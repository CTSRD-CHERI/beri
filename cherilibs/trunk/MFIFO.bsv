/*-
 * Copyright (c) 2012 SRI International
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
 *
 ******************************************************************************
 *
 * Author: Nirav Dave <ndave@csl.sri.com>
 * 
 ******************************************************************************
 * Description:
 * 
 * FIFO with predicated lookup
 * 
 ******************************************************************************/

import FIFO::*;
import FIFOF::*;

interface MFIFO#(type a);
  method Action enq(a x);
  method ActionValue#(Maybe#(a)) mdeq();
endinterface

module mkMFIFO(MFIFO#(a)) provisos(Bits#(a, asz));
  FIFOF#(a) _f <- mkUGFIFOF();
  
  method Action enq(a x) if (_f.notFull);
	_f.enq(x);
  endmethod
  
  method ActionValue#(Maybe#(a)) mdeq();
	if (_f.notEmpty)
	  return Invalid;
	else
	  begin
        let x = _f.first();
		_f.deq();
		return Valid (x);
	  end
  endmethod
  
endmodule
