/*
 * Copyright 2015 Matthew Naylor
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
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream
 * Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
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

import MIPS :: *;
import MemTypes :: *;
import StmtFSM   :: *;
import BlueCheck :: *;
import Vector::*;

function Bit#(n) reverseBytes(Bit#(n) x) provisos (Mul#(8,n8,n));
  Vector#(n8,Bit#(8)) vx = unpack(x);
  return pack(Vector::reverse(vx));
endfunction

function Bit#(outSize) selectF(Bit#(lineSize) val, Bit#(lineAddrSize) off) 
  provisos (Add#(a__, outSize, lineSize), 
  Mul#(8,n8,lineSize), Add#(b__, 3, lineAddrSize));
  //Vector#(n8,Bit#(8)) vx = unpack(val);
  //vx = shiftOutFrom0(?,vx, off>>3);
  //return truncate(pack(vx));
  Bit#(lineAddrSize) sa = off;
  sa[2:0] = 0;
  return truncate(val >> sa);
endfunction

function SizedWord selectWithSizeStandard(Bit#(64) oldReg, Line line, CheriPhyBitOffset addr, MemSize size, Bool sExtend);

  // Addr is the BIT ADDRESS of the desired data item.
  CheriPhyBitOffset addrMask = case(size)
                                 WordLeft, WordRight: return truncate(8'hE0);
                                 DoubleWordLeft, DoubleWordRight: return truncate(8'hC0);
                                 default: return truncate(8'hF8);
                               endcase;
  let extendFN = (sExtend) ? signExtend : zeroExtend;
  CheriPhyBitOffset nadder = addr & truncate(8'hF8);
  Line shiftedLine = reverseBytes(selectF(line, nadder & addrMask));
  case(size)
    Byte: begin
      Bit#(8) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord extendFN(temp);
    end
    HalfWord: begin
      Bit#(16) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord extendFN(temp);
    end
    Word: begin
      Bit#(32) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord extendFN(temp);
    end
    WordLeft: begin
      Bit#(32) orig = oldReg[31:0];
      Bit#(32) temp = truncateLSB(shiftedLine);
      Bit#(5) shift = truncate(nadder);
      temp = temp << shift;
      Bit#(32) mask = 32'hFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord extendFN(temp);
    end
    WordRight: begin
      Bit#(32) orig = oldReg[31:0];
      Bit#(32) temp = truncateLSB(shiftedLine);
      Bit#(5) shift = (24 - truncate(nadder));
      temp = temp >> shift;
      Bit#(32) mask = 32'hFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord extendFN(temp);
    end
    // This is the default case
    /*DoubleWord: begin
      Bit#(64) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord temp;
    end*/
    DoubleWordLeft: begin
      Bit#(64) orig = oldReg;
      Bit#(64) temp = truncateLSB(shiftedLine);
      Bit#(6) shift = truncate(nadder);
      temp = temp << shift;
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord temp;
    end
    DoubleWordRight: begin
      Bit#(64) orig = oldReg;
      Bit#(64) temp = truncateLSB(shiftedLine);
      Bit#(6) shift = 56 - truncate(nadder);
      temp = temp >> shift;
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord temp;
    end
    `ifdef USECAP
      CapWord: begin
        Bit#(CapWidth) temp = truncateLSB(shiftedLine);
        return tagged CapLine temp;
      end
    `endif
    default: begin
      Bit#(64) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord temp;
    end
  endcase
endfunction

function Bit#(n) rotateAndReverseBytes(Bit#(n) x, UInt#(TSub#(TLog#(n),3)) rotate)
  provisos (Mul#(8,n8,n), Log#(n8, TSub#(TLog#(n), 3)));
  Vector#(n8,Bit#(8)) vx = unpack(x);
  // Rotate (left) by the two's complement of the input to simulate a rotate right.
  vx = rotateBy(vx, ~rotate+1);
  return pack(Vector::reverse(vx));
endfunction

function SizedWord selectWithSize(Bit#(64) oldReg, Line line, CheriPhyBitOffset addr, MemSize size, Bool sExtend);

  // Addr is the BIT ADDRESS of the desired data item.
  CheriPhyBitOffset naddr  = addr & truncate(8'hF8);
  // Shift amount address that will take into account Left and Right loads
  CheriPhyByteOffset snaddr = truncateLSB(naddr);
  if (size==WordRight)            snaddr = snaddr - 3;
  else if (size==DoubleWordRight) snaddr = snaddr - 7;
  let extendFN = (sExtend) ? signExtend : zeroExtend;
  Line shiftedLine = rotateAndReverseBytes(line, unpack(snaddr));
  case(size)
    Byte: begin
      Bit#(8) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord extendFN(temp);
    end
    HalfWord: begin
      Bit#(16) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord extendFN(temp);
    end
    Word: begin
      Bit#(32) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord extendFN(temp);
    end
    WordLeft: begin
      Bit#(32) orig = oldReg[31:0];
      Bit#(32) temp = truncateLSB(shiftedLine);
      Bit#(5) shift = truncate(naddr);
      //temp = temp << shift;
      Bit#(32) mask = 32'hFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord extendFN(temp);
    end
    WordRight: begin
      Bit#(32) orig = oldReg[31:0];
      Bit#(32) temp = truncateLSB(shiftedLine);
      Bit#(5) shift = 24 - truncate(naddr);
      //temp = temp >> shift;
      Bit#(32) mask = 32'hFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord extendFN(temp);
    end
    // This is the default case
    /*DoubleWord: begin
      Bit#(64) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord temp;
    end*/
    DoubleWordLeft: begin
      Bit#(64) orig = oldReg;
      Bit#(64) temp = truncateLSB(shiftedLine);
      Bit#(6) shift = truncate(naddr);
      //temp = temp << shift;
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF << shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord temp;
    end
    DoubleWordRight: begin
      Bit#(64) orig = oldReg;
      Bit#(64) temp = truncateLSB(shiftedLine);
      Bit#(6) shift = 56 - truncate(naddr);
      //temp = temp >> shift;
      Bit#(64) mask = 64'hFFFFFFFFFFFFFFFF >> shift;
      temp = (temp & mask) | (orig & ~mask);
      return tagged DoubleWord temp;
    end
    `ifdef USECAP
      CapWord: begin
        Bit#(CapWidth) temp = truncateLSB(shiftedLine);
        return tagged CapLine temp;
      end
    `endif
    default: begin
      Bit#(64) temp = truncateLSB(shiftedLine);
      return tagged DoubleWord temp;
    end
  endcase
endfunction

module [Specification] selectWithSizeSpec ();
  function ActionValue#(Bool) testFunc(Line l) =
    actionvalue
      Bit#(64) oldReg = truncate(l); 
      Line line = l;
      MemSize size = unpack(truncate(l));
      CheriPhyByteOffset addr = truncate(l);
      // Align addresses.
      case (size)
        HalfWord:   addr = addr&truncate(8'hFE);
        Word:       addr = addr&truncate(8'hFC);
        DoubleWord: addr = addr&truncate(8'hF8);
        Byte, WordLeft, WordRight, DoubleWordLeft, DoubleWordRight: addr = addr;
        default:    addr = addr&truncate(8'hF8);
      endcase
      Bool sExtend = unpack(truncateLSB(l));
    	$display(" --- New Try --- ");
    	$display("oldReg: %x, line: %x, addr: %x, size: %s, sExtend: %d ", 
                oldReg,     line,     addr, memSizeString(size),     sExtend);
    	$display(" --- ");
    	$display("Standard: ", fshow(selectWithSizeStandard(oldReg, line, {addr, 3'b0}, size, sExtend)));
    	$display(" --- ");
    	$display("Implemen: ", fshow(selectWithSize(oldReg, line, {addr, 3'b0}, size, sExtend)));
    	$display(" --- ");
    	return selectWithSizeStandard(oldReg, line, {addr, 3'b0}, size, sExtend) == selectWithSize(oldReg, line, {addr, 3'b0}, size, sExtend);
    endactionvalue;

  prop("testFunc", testFunc);
endmodule

module selectWithSizeCheck ();
  BlueCheck_Params params = bcParams;
  params.numIterations = 100000;
  Stmt s <- mkModelChecker(selectWithSizeSpec, params);
  mkAutoFSM(s);
endmodule
