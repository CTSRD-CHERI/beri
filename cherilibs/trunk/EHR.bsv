/*-
 * Copyright (c) 2009-2011 Nirav Dave
 * Copyright (c) 2011-2013 SRI International
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
 * Authors:
 *   Nirav Dave <ndave@ndave.org / ndave@csl.sri.com>
 *
 ******************************************************************************
 *
 * Description: Parameterized Ephemeral History Register Implementation
 *
******************************************************************************/

import Vector::*;
//import CReg  ::*;

typedef  Vector#(n_sz, Reg#(alpha)) EHR#(type n_sz, type alpha);

`ifndef VERIFY

module mkEHR#(a init)(EHR#(n, a))
   provisos (Bits#(a,sa));
   let nn = valueof(n);

   Reg#(a) rs[nn];
   rs <- mkCReg(nn, init);
   return arrayToVector(rs);
endmodule

module mkEHRU(EHR#(n, a))
   provisos (Bits#(a,sa));
   let nn = valueof(n);

   Reg#(a) rs[nn];
   rs <- mkCRegU(nn);
   return arrayToVector(rs);
endmodule


`else //VERIFY

module mkEHR#(alpha init)(EHR#(n,alpha)) provisos(Bits#(alpha, asz));
  Reg#(alpha) r <- mkReg(init);

  return (replicate(r));
endmodule

module mkEHRU(EHR#(n,alpha)) provisos(Bits#(alpha, asz));
  Reg#(alpha) r <- mkRegU;

  return (replicate(r));
endmodule

`endif
