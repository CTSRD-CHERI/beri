/*-
 * Copyright (c) 2014 Matthew Naylor
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
 */
 
import Vector :: *;

typedef struct {
  keyType key;
  datType dat;
} Entry#(type keyType, type datType) deriving (Bits, Eq, Bounded, FShow);

interface Bag#(numeric type numElems, type keyType, type datType);
  method Maybe#(datType) isMember(keyType x);
  method Action          insert(keyType x, datType d);
  method Bool            full;
  method Action          remove(keyType x);
endinterface

module mkSmallBag (Bag#(numElems, keyType, datType))
  provisos ( Bits#(keyType, keyTypeSize)
           , Bits#(datType, datTypeSize)
           , Eq#(keyType) 
           , FShow#(Maybe#(Bag::Entry#(keyType, datType))));

  // A small bag of elements, stored in registers
  Reg#(Vector#(numElems, Maybe#(Entry#(keyType, datType)))) bag <-
    mkReg(replicate(tagged Invalid));
  
  // An item to be inserted
  Wire#(Maybe#(Entry#(keyType, datType))) insertItem <- mkDWire(tagged Invalid);

  // An item to be removed
  Wire#(Maybe#(keyType)) removeItem <- mkDWire(tagged Invalid);

  rule updateBag;
    Bool inserted = False;
    Integer insert = 0;
    Vector#(numElems, Maybe#(Entry#(keyType, datType))) newBag = bag;
    for (Integer i = 0; i < valueOf(numElems); i=i+1) begin
      //$display("<time %0t, core %d, Bag> Search %x ", fromInteger(i), fshow(bag[i]));
      if (bag[i] matches tagged Valid .ent) begin
        if (removeItem matches tagged Valid .itm &&& ent.key == itm)
          newBag[i] = tagged Invalid;
        if (insertItem matches tagged Valid .itm &&& ent.key == itm.key && !inserted) begin
          newBag[i] = insertItem;
          inserted = True;
        end
      end
    end
    for (Integer i = 0; i < valueOf(numElems); i=i+1) begin
      if (!inserted && !isValid(bag[i])) begin
        newBag[i] = insertItem;
        inserted = True;
      end
    end
    bag <= newBag;
  endrule

  method Maybe#(datType) isMember(keyType x);
    Maybe#(datType) ret = tagged Invalid;
    for (Integer i = 0; i < valueOf(numElems); i=i+1) begin
      if (bag[i] matches tagged Valid .ent &&& ent.key == x)
        ret = tagged Valid ent.dat;
    end
    return ret;
  endmethod

  method Action insert(keyType x, datType d);
    insertItem <= tagged Valid Entry{key: x, dat: d};
  endmethod
  
  method Bool full;
    return all(isValid, bag);
  endmethod

  method Action remove(keyType x);
    removeItem <= tagged Valid x;
  endmethod

endmodule
