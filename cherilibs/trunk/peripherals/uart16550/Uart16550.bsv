/*-
 * Copyright (c) 2013 Simon W. Moore
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
 * UART16550
 * =========
 * Simon Moore, July 2013
 * 
 * This Bluespec module implements a 16650 style UART for RS232 serial
 * communication.
 * 
 * The following registers exist at 32-bit boundaries accessible in little
 * endian byte order:
 * 
 * Offset   Name            Read/Write   Description
 *   0      UART_DATA          RW        write to transmit, read to receive
 *   1      UART_INT_ENABLE    RW        interrupt enable
 *   2      UART_INT_ID        R         interrupt identification
 *   2      UART_FIFO_CTRL      W        FIFO control
 *   3      UART_LINE_CTRL     RW        line control
 *   4      UART_MODEM_CTRL     W        modem control
 *   5      UART_LINE_STATUS   R         line status
 *   6      UART_MODEM_STATUS  R         modem status
 *   7      UART_SCRATCH       RW        scratch register
 ******************************************************************************/

package Uart16550;

import FIFO::*;
import FIFOF::*;
import FIFOLevel::*;
import GetPut::*;
import ClientServer::*;
import Avalon2ClientServer::*;


// depth of transmit and receive FIFOs
typedef 16 Tx_FIFO_depth;
typedef 16 Rx_FIFO_depth;

// enumerate addresses corresponding to device registers
typedef enum {
   UART_ADDR_DATA=0,
   UART_ADDR_INT_ENABLE=1,
   UART_ADDR_INT_ID_FIFO_CTRL=2, // read=INT_ID, write=FIFO_CTRL
   UART_ADDR_LINE_CTRL=3,
   UART_ADDR_MODEM_CTRL=4,
   UART_ADDR_LINE_STATUS=5,
   UART_ADDR_MODEM_STATUS=6,
   UART_ADDR_SCRATCH=7
   } UART_ADDR_T deriving (Bits, Eq, FShow);

// interrupt enable register bits
typedef struct {
   Bool uart_IE_MS;     // Modem status interrupt
   Bool uart_IE_RLS;    // Receiver line status interrupt
   Bool uart_IE_THRE;   // Transmitter holding register empty interrupt
   Bool uart_IE_RDA;    // Recived data available interrupt
   } UART_IE_T deriving (Bits, Eq, FShow);

// interrupt identification values
typedef enum {
   UART_II_MS     = 4'b0000,      // modem status
   UART_II_NO_INT = 4'b0001,      // no interrupt pending
   UART_II_THRE   = 4'b0010,      // transmitter holding register empty
   UART_II_RDA    = 4'b0100,      // receiver data available
   UART_II_RLS    = 4'b0110,      // receiver line status
   UART_II_TI     = 4'b1100       // timeout indication
   } UART_II_T deriving (Bits, Eq, FShow);

// line control register bits
typedef struct {
   Bit#(1) uart_LC_DL;   // divisor latch access bit
   Bit#(1) uart_LC_BC;   // break control
   Bit#(1) uart_LC_SP;   // stick parity
   Bit#(1) uart_LC_EP;   // even parity
   Bit#(1) uart_LC_PE;   // parity enables
   Bit#(1) uart_LC_SB;   // stop bits
   Bit#(2) uart_LC_BITS; // bits in character
   } UART_LC_T deriving (Bits, Eq, FShow);

// modem control register bits
typedef struct {
   bit uart_MC_LOOPBACK;
   bit uart_MC_OUT2;
   bit uart_MC_OUT1;
   bit uart_MC_RTS;
   bit uart_MC_DTR;
   } UART_MC_T deriving (Bits, Eq, FShow);

// line status register bits
typedef struct {
   Bool uart_LS_EI;        // error indicator
   Bool uart_LS_TW;        // transmitter empty indicator
   Bool uart_LS_TFE;       // transmitter FIFO is empty
   Bool uart_LS_BI;        // break interrupt
   Bool uart_LS_FE;        // framing error
   Bool uart_LS_PE;        // parity error
   Bool uart_LS_OE;        // overrun error
   Bool uart_LS_DR;        // data ready
   } UART_LS_T deriving (Bits, Eq, FShow);

// modem status register bits
typedef struct {
   bit uart_MS_CDCD;       // complement signals
   bit uart_MS_CRI;
   bit uart_MS_CDSR;
   bit uart_MS_CCTS;      
   bit uart_MS_DDCD;       // delta signals
   bit uart_MS_TERI;
   bit uart_MS_DDSR;
   bit uart_MS_DCTS;
   } UART_MS_T deriving (Bits, Eq, FShow);

// data from receiver
typedef struct {
   Bit#(8) data;
   Bool break_error;
   Bool parity_error;
   Bool framing_error;
   } RX_DATA_T deriving (Bits, Eq);

// transmitter states
typedef enum {
   STX_idle, STX_pop_byte, STX_send_start, STX_send_byte, STX_send_parity, STX_send_stop
   } TX_state_T deriving (Bits, Eq, FShow);

// receiver states
typedef enum {
   SRX_idle, SRX_rec_start, SRX_rec_bit, SRX_rec_parity, SRX_rec_stop,
   SRX_check_parity, SRX_rec_prepare, SRX_end_bit, SRX_wait1,
   SRX_ca_lc_parity, SRX_push } RX_state_T deriving (Bits, Eq, FShow);


(* always_ready, always_enabled *)
interface RS232_PHY_Ifc;
  method Action modem_input(bit srx, bit cts, bit dsr, bit ri, bit dcd);
  method bit modem_output_stx;
  method bit modem_output_rts;
  method bit modem_output_dtr;
endinterface


interface Uart16550_Avalon_Ifc;
  interface RS232_PHY_Ifc coe_rs232;
  interface AvalonSlaveIfc#(3) avs;
  (* always_ready, always_enabled *) method bit irq;
endinterface


(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkUart16550_Avalon(Uart16550_Avalon_Ifc);
  
  AvalonSlave2ClientIfc#(3) bus <- mkAvalonSlave2Client;
  
  UART_transmitter_ifc uart_tx <- mkUART_transmitter;
  UART_receiver_ifc    uart_rx <- mkUART_receiver;
  
  // TODO: FIXME: use Tx_FIFO_depth and Rx_FIFO_depth rather than 16?
  // TX should only have a 1 element FIFO
  //  FIFOCountIfc#(Bit#(8),   16)   tx_fifo <- mkGFIFOCount(True, False, True);
  FIFOF#(Bit#(8))                tx_fifo <- mkGFIFOF1(True, False);
  FIFOCountIfc#(RX_DATA_T, 16)   rx_fifo <- mkGFIFOCount(True, True,  True);
  PulseWire             tx_fifo_clear_pw <- mkPulseWire;
  PulseWire             rx_fifo_clear_pw <- mkPulseWire;
  // add some bypass wires to hack around scheduling loop
  Wire#(Bool)               rx_fifo_full <- mkBypassWire;
  Wire#(Bool)              rx_fifo_empty <- mkBypassWire;
  Wire#(Bool)              tx_fifo_empty <- mkBypassWire;
  // provide first item of rx_fifo if there is one, otherwise a default
  Wire#(RX_DATA_T)         rx_fifo_first <- mkBypassWire;
  
  PulseWire    count_error_up <- mkPulseWire;
  PulseWire  count_error_down <- mkPulseWire;
  PulseWire count_error_clear <- mkPulseWire;
  Reg#(UInt#(TAdd#(Rx_FIFO_depth,1)))
                  count_error <- mkReg(0);

  Reg#(Bit#(2))           fcr <- mkReg(2'b11);     // upper 2 bits of FIFO control register (rest not stored)
  Reg#(UART_IE_T)         ier <- mkReg(unpack(0)); // interrupt enable register bits (disable after reset)
  Reg#(UART_LC_T)         lcr <- mkReg(unpack('b00000011)); // line control register (default 8n1 format)
  Reg#(UART_MC_T)         mcr <- mkReg(unpack(0)); // modem control register
  Wire#(UART_MC_T)  mc_bypass <- mkBypassWire;
  Reg#(UART_LS_T)         lsr <- mkReg(unpack(0)); // line status register
  Reg#(UART_MS_T)         msr <- mkReg(unpack(0)); // modem status register
  Reg#(Bit#(8))       scratch <- mkReg(unpack(0)); // scratch register

  Wire#(Bool)        loopback <- mkBypassWire;     // loopback mode (msr[4])
  
  Reg#(Bit#(8))          dl1r <- mkReg(0);         // divisor 1 register
  Reg#(Bit#(8))          dl2r <- mkReg(0);         // divisor 2 register
  Reg#(Bit#(16))          dlc <- mkReg(0);         // divisor counter
  Reg#(Bit#(16))           dl <- mkReg(0);         // divisor counter bound
  Reg#(Bool)           enable <- mkReg(False);
  Wire#(Maybe#(Bit#(16)))
                    dl_update <- mkDWire(tagged Invalid);

  PulseWire      interrupt_pw <- mkPulseWireOR;
  RS_ifc              rls_int <- mkRS;
  RS_ifc              rda_int <- mkRS;
  RS_ifc             thre_int <- mkRS;
  RS_ifc               ms_int <- mkRS;
  RS_ifc               ti_int <- mkRS;

  // synchroniser registers for input pins
  Reg#(bit)      pin_srx_sync <- mkReg(0);
  Reg#(bit)      pin_cts_sync <- mkReg(0);
  Reg#(bit)      pin_dsr_sync <- mkReg(0);
  Reg#(bit)      pin_ri_sync  <- mkReg(0);
  Reg#(bit)      pin_dcd_sync <- mkReg(0);

  // registers for stable input pin values pre loopback check
  Reg#(bit)         pin_srx_c <- mkReg(0);
  Reg#(bit)         pin_cts_c <- mkReg(0);
  Reg#(bit)         pin_dsr_c <- mkReg(0);
  Reg#(bit)         pin_ri_c  <- mkReg(0);
  Reg#(bit)         pin_dcd_c <- mkReg(0);

  // registers for stable input pin values
  Reg#(bit)           pin_srx <- mkReg(0);
  Reg#(bit)           pin_cts <- mkReg(0);
  Reg#(bit)           pin_dsr <- mkReg(0);
  Reg#(bit)           pin_ri  <- mkReg(0);
  Reg#(bit)           pin_dcd <- mkReg(0);

  // previous pin values last read via MSR (modem status register)
  Reg#(bit)          prev_cts <- mkReg(0);
  Reg#(bit)          prev_dsr <- mkReg(0);
  Reg#(bit)          prev_ri  <- mkReg(0);
  Reg#(bit)          prev_dcd <- mkReg(0);
  PulseWire msr_save_pin_state <- mkPulseWire; // trigger condition to save pin state
  
  // registered outputs
  Reg#(bit)           pin_stx <- mkReg(0);
  Reg#(bit)           pin_rts <- mkReg(0);
  Reg#(bit)           pin_dtr <- mkReg(0);

  (* no_implicit_conditions *)
  rule synchronise_input_pins; // N.B. there must be no logic between these registers
    pin_srx_c <= pin_srx_sync;
    pin_cts_c <= pin_cts_sync;
    pin_dsr_c <= pin_dsr_sync;
    pin_ri_c  <= pin_ri_sync;
    pin_dcd_c <= pin_dcd_sync;
  endrule

  rule bypass_mrc_to_avoid_scheduling_loop;
    mc_bypass <= mcr;
  endrule
  
  (* no_implicit_conditions *)
  rule handle_loopback_mode;
    if(loopback)
      begin
	pin_srx <= pin_stx;
	pin_cts <= mc_bypass.uart_MC_RTS;
	pin_dsr <= mc_bypass.uart_MC_DTR;
	pin_ri  <= mc_bypass.uart_MC_OUT1;
	pin_dcd <= mc_bypass.uart_MC_OUT2;
      end
    else
      begin
	pin_srx <= pin_srx_c;
	pin_cts <= pin_cts_c;
	pin_dsr <= pin_dsr_c;
	pin_ri  <= pin_ri_c;
	pin_dcd <= pin_dcd_c;
      end

    msr <= UART_MS_T{
       // first changes in the pins
       uart_MS_DCTS: pin_cts ^ prev_cts,
       uart_MS_DDSR: pin_dsr ^ prev_dsr,
       uart_MS_TERI: pin_ri  ^ prev_ri,
       uart_MS_DDCD: pin_dcd ^ prev_dcd,
       // then the actual signals
       uart_MS_CCTS: pin_cts,  // TODO: allow this to be from loopback
       uart_MS_CDSR: pin_dsr,
       uart_MS_CRI:  pin_ri,
       uart_MS_CDCD: pin_dcd};

    if(msr_save_pin_state)
      begin
	prev_dcd <= pin_dcd;
	prev_ri  <= pin_ri;
	prev_dsr <= pin_dsr;
	prev_cts <= pin_cts;
      end
  endrule
  
  (* no_implicit_conditions *)
  rule output_rts_dtr;
    pin_rts <= mcr.uart_MC_RTS;
    pin_dtr <= mcr.uart_MC_DTR;
  endrule
  
  (* no_implicit_conditions *)
  rule loopback_mode_select;
    loopback <= mcr.uart_MC_LOOPBACK==1;
  endrule

  (* no_implicit_conditions *)
  rule connect_pins_rx;
    uart_rx.input_srx(pin_srx);
  endrule
  (* no_implicit_conditions *)
  rule connect_pins_tx;
    pin_stx <= uart_tx.output_stx;
  endrule
  (* no_implicit_conditions *)
  rule rx_first_item_if_any;
    rx_fifo_first <= rx_fifo.notEmpty ? rx_fifo.first
                                      : RX_DATA_T{
					 data:0,
					 break_error: False,
					 parity_error: False,
					 framing_error: False};
  endrule    
  
  (* no_implicit_conditions *)
  rule interrupt_sources;
    if(rda_int.state || rls_int.state || thre_int.state || ms_int.state || ti_int.state)
      interrupt_pw.send;
    
    // receiver line status interrupt
    //  - note: also reset on read of line status
    if(!ier.uart_IE_RLS)
      rls_int.reset;
    else if(rx_fifo_full
	    || rx_fifo_first.parity_error
	    || rx_fifo_first.framing_error
	    || rx_fifo_first.break_error)
      rls_int.posedge_set;
    
    // received data available interrupt
    UInt#(5) trigger_level;
    case(fcr)
      // 2'b00 handled by default case
      2'b01   : trigger_level = 4;
      2'b10   : trigger_level = 8;
      2'b11   : trigger_level = 14;
      default : trigger_level = 1;
    endcase
    // TODO: should this in fact be edge triggered on the trigger level being reached or passed?
    if(ier.uart_IE_RDA && !rx_fifo_empty && (rx_fifo.count >= trigger_level))
      rda_int.set;
    else
      rda_int.reset;

    // transmitter holding register empty interrupt
//    if(!ier.uart_IE_THRE)
    if(!ier.uart_IE_THRE || !tx_fifo_empty)
      thre_int.reset;
    else if(tx_fifo_empty)
      thre_int.posedge_set;
    
    // timer interrupt
    if(!ier.uart_IE_RDA)
      ti_int.reset;
    else if(uart_rx.timeout)
      ti_int.posedge_set;
    
    // modem status interrupt
    //  - note: also reset by reading modem status
    if(!ier.uart_IE_MS)
      ms_int.reset;
    else if({msr.uart_MS_DCTS, msr.uart_MS_DDSR, msr.uart_MS_TERI, msr.uart_MS_DDCD} != 0)
      ms_int.posedge_set;
  endrule
  
  (* no_implicit_conditions *)
  rule foward_lc_enable;
    uart_tx.control(lcr, enable);
    uart_rx.control(lcr, enable);
  endrule
  
  (* no_implicit_conditions *)
  rule divisor_counter;
    enable <= (dlc==0) && (dl>0);
    if(isValid(dl_update))
      begin
        let newdl = fromMaybe(?, dl_update);
        dl <= newdl;
        dlc <= newdl-1;
        $display("%05t: dl set to %1d", $time, newdl);
      end
    else
      dlc <= (dlc==0 ? dl : dlc) - 1;
  endrule

  (* no_implicit_conditions *)
  rule forward_tx_clear(tx_fifo_clear_pw);
    tx_fifo.clear;
  endrule
  rule forward_tx(!tx_fifo_clear_pw && tx_fifo.notEmpty);
    uart_tx.tx_char(tx_fifo.first);
    tx_fifo.deq;
  endrule
  
  rule forward_rx;
    if(rx_fifo_clear_pw)
      rx_fifo.clear;
    else if(rx_fifo.notFull)
      begin
	RX_DATA_T rx <- uart_rx.rx_char;
	rx_fifo.enq(rx);
	if(rx.break_error || rx.parity_error || rx.framing_error)
	  count_error_up.send();
      end
  endrule

  (* no_implicit_conditions *)
  rule count_rx_errors;
    if(count_error_clear)
      count_error <= 0;
    else
      begin
	if(count_error_up && !count_error_down && (count_error<fromInteger(valueOf(Rx_FIFO_depth))))
	  count_error <= count_error+1;
	if(!count_error_up && count_error_down && (count_error>0))
	  count_error <= count_error-1;    
      end
  endrule
  
  (* no_implicit_conditions *)
  rule fifo_status_bypass_to_avoid_scheduling_loop;
    rx_fifo_full  <= !rx_fifo.notFull;
    rx_fifo_empty <= !rx_fifo.notEmpty;
    tx_fifo_empty <= !tx_fifo.notEmpty;
  endrule
  
  rule handle_avalon_accesses;
    Bool dlab = lcr.uart_LC_DL == 1'b1; // divisor latch enable

    let ls = UART_LS_T{
       uart_LS_EI:  rx_fifo_full || (count_error!=0),       // error indicator
       uart_LS_TW:  tx_fifo_empty && uart_tx.tx_buf_empty,  // transmitter empty
       uart_LS_TFE: tx_fifo_empty,                          // transmitter FIFO empty
       uart_LS_BI:  rx_fifo_first.break_error,              // break error
       uart_LS_FE:  rx_fifo_first.framing_error,            // framing error
       uart_LS_PE:  rx_fifo_first.parity_error,             // parity error
       uart_LS_OE:  rx_fifo_full,                           // overflow
       uart_LS_DR: !rx_fifo_empty};                         // data ready
  
    lsr <= ls;

    UART_II_T ii;
    if(rls_int.state)       // highest priority interrupt - receiver line status
      ii = UART_II_RLS;
    else if(rda_int.state)  // second priority interrupt - received data available
      ii = UART_II_RDA;
    else if(ti_int.state)   // also second priority - timeout
      ii = UART_II_TI;
    else if(thre_int.state) // third priority - transmitter holding register empty
      ii = UART_II_THRE;
    else if(ms_int.state)   // fourth - modem status change interrupt
      ii = UART_II_MS;
    else
      ii = UART_II_NO_INT;
    
    let req <- bus.client.request.get();
    UART_ADDR_T addr = unpack(pack(req.addr));
    Bit#(8) d = truncate(pack(req.data));
    Bit#(8) rtn=0;
    Bool rtn_valid=True;
    case(tuple2(addr, req.rw))
      tuple2(UART_ADDR_DATA, MemRead): if(dlab) // divisor latch enabled
					 rtn = dl1r;
				       else if(!rx_fifo_empty)
					 begin
					   RX_DATA_T rx = rx_fifo.first;
					   rtn = rx.data;
					   if(rx.break_error || rx.parity_error || rx.framing_error)
					     count_error_down.send;
					   rx_fifo.deq;
					   ti_int.reset;
					   rda_int.reset;
					 end
				       else
					 rtn_valid = False; // TODO: should this be the old value?
      tuple2(UART_ADDR_DATA, MemWrite): if(dlab) // divisor latch enabled
					  begin
					    dl1r <= d;
					    dl_update <= tagged Valid ({dl2r,d});
					  end
					else if(tx_fifo.notFull)
					  begin
					    tx_fifo.enq(unpack(d));
					    thre_int.reset;
					  end
      tuple2(UART_ADDR_INT_ENABLE,       MemRead):  rtn = dlab ? dl2r : zeroExtend(pack(ier));
      tuple2(UART_ADDR_INT_ENABLE,       MemWrite): if(dlab)
							dl2r <= unpack(d);
						    else
							ier <= unpack(truncate(d));
      tuple2(UART_ADDR_INT_ID_FIFO_CTRL, MemRead):  rtn = {4'b1100, pack(ii)};
      tuple2(UART_ADDR_INT_ID_FIFO_CTRL, MemWrite): begin
						      fcr <= d[7:6];
						      if(d[1]==1'b1)
							begin
							  rx_fifo_clear_pw.send;
							  count_error_clear.send;
							end
						      if(d[2]==1'b1)
							tx_fifo_clear_pw.send;
						    end
      tuple2(UART_ADDR_LINE_CTRL,        MemRead):  rtn = pack(lcr);
      tuple2(UART_ADDR_LINE_CTRL,        MemWrite): lcr <= unpack(truncate(pack(req.data)));
      tuple2(UART_ADDR_MODEM_CTRL,       MemRead):  rtn = zeroExtend(pack(mcr));
      tuple2(UART_ADDR_MODEM_CTRL,       MemWrite): mcr <= unpack(truncate(pack(req.data)));
      tuple2(UART_ADDR_LINE_STATUS,      MemRead):  begin
						      rls_int.reset;
						      rtn = pack(ls);
						    end
      tuple2(UART_ADDR_LINE_STATUS,      MemWrite): begin /* no write */ end
      tuple2(UART_ADDR_MODEM_STATUS,     MemRead):  begin
						      ms_int.reset;
						      rtn = pack(msr);
						      msr_save_pin_state.send();
						    end
      tuple2(UART_ADDR_MODEM_STATUS,     MemWrite): begin /* no write */ end
      tuple2(UART_ADDR_SCRATCH,          MemRead):  rtn = scratch;
      tuple2(UART_ADDR_SCRATCH,          MemWrite): scratch <= d;
    endcase
    bus.client.response.put(req.rw==MemWrite ? tagged Invalid :
			           rtn_valid ? tagged Valid zeroExtend(unpack(rtn))
						 : tagged Valid 32'hffffffff);
  endrule

  interface RS232_PHY_Ifc coe_rs232;
    method Action modem_input(bit srx, bit cts, bit dsr, bit ri, bit dcd);
      pin_srx_sync <= srx;
      pin_cts_sync <= cts;
      pin_dsr_sync <= dsr;
      pin_ri_sync  <= ri;
      pin_dcd_sync <= dcd;
    endmethod
    method bit modem_output_stx = pin_stx;
    method bit modem_output_rts = pin_rts;
    method bit modem_output_dtr = pin_dtr;
  endinterface
  
  interface avs = bus.avs;

  method bit irq;
    return interrupt_pw ? 1'b1 : 1'b0;
  endmethod
  
endmodule




//////////////////////////////////////////////////////////////////////////////
// transmitter

interface UART_transmitter_ifc;
  method Action tx_char(Bit#(8) c);
  (* always_ready, always_enabled *)
  method Bool tx_buf_empty;
  (* always_ready, always_enabled *)
  method Action control(UART_LC_T lc_in, Bool enable_in);
  (* always_ready, always_enabled *)
  method bit output_stx;
endinterface


module mkUART_transmitter(UART_transmitter_ifc);

  FIFOF#(Bit#(8))      tx_fifo <- mkLFIFOF;
  Wire#(Bool)    tx_fifo_empty <- mkBypassWire;
  Reg#(bit)            bit_out <- mkReg(0);
  Reg#(bit)         parity_xor <- mkReg(0);
  Reg#(bit)          stx_o_tmp <- mkReg(1); // rename output bit? our use bit_out directly?
  Reg#(TX_state_T)      tstate <- mkReg(STX_idle);
  Reg#(TX_state_T) last_tstate <- mkReg(STX_idle);
  Reg#(UInt#(5))       counter <- mkReg(0);
  Reg#(UInt#(3))   bit_counter <- mkReg(0);
  Reg#(Bit#(7))      shift_out <- mkReg(0);
  Wire#(UART_LC_T)          lc <- mkBypassWire;
  Wire#(Bool)           enable <- mkBypassWire;
  
  rule monitor_state_for_debug(last_tstate != tstate);
    /*
    $write("%05t: UART TX state change ", $time);
    $write(fshow(last_tstate));
    $write(" -> ");
    $display(fshow(tstate));
     */
    last_tstate <= tstate;
  endrule
 
  // rule to decouple rule dependency on tx_fifo.notEmpty 
  (* no_implicit_conditions *)
  rule forward_tx_fifo_empty;
    tx_fifo_empty <= !tx_fifo.notEmpty;
  endrule
  
  rule idle(enable && (tstate==STX_idle));
    tstate <= STX_pop_byte; // move directly to pop_byte since it will block if the tx_fifo is empty
    stx_o_tmp <= 1;
  endrule
  
  rule pop_byte(enable && (tstate==STX_pop_byte));
    case(lc.uart_LC_BITS) // number of bits in a word
      0: begin
	   bit_counter <= 4;
	   parity_xor <= ^tx_fifo.first[4:0];
	 end
      1: begin
	   bit_counter <= 5;
	   parity_xor <= ^tx_fifo.first[5:0];
	 end
      2: begin
	   bit_counter <= 6;
	   parity_xor <= ^tx_fifo.first[6:0];
	 end
      3: begin
	   bit_counter <= 7;
	   parity_xor <= ^tx_fifo.first[7:0];
	 end
    endcase
    shift_out[6:0] <= tx_fifo.first[7:1];
    bit_out <= tx_fifo.first[0];
    tstate <= STX_send_start;
  endrule
  
  rule send_start(enable && (tstate==STX_send_start));
    if(counter==0)
      counter <= 5'b01111;
    else if(counter==1)
      begin
	counter <= 0;
	tstate <= STX_send_byte;
      end
    else
      counter <= counter-1;
    stx_o_tmp <= 0;
  endrule

  rule send_byte(enable && (tstate==STX_send_byte));
    if(counter==0)
      counter <= 5'b01111;
    else if(counter==1)
      begin
	if(bit_counter > 0)
	  begin
	    bit_counter <= bit_counter-1;
	    shift_out <= {1'b0,shift_out[6:1]};
	    bit_out <= shift_out[0];
	  end
	else // end of byte
	  if(lc.uart_LC_PE == 0) // no partity bit
	    tstate <= STX_send_stop;
	  else
	    begin
	      case({lc.uart_LC_EP, lc.uart_LC_SP})
		2'b00: bit_out <= ~parity_xor;
		2'b01: bit_out <= 1;
		2'b10: bit_out <= parity_xor;
		2'b11: bit_out <= 0;
	      endcase
	      tstate <= STX_send_parity;
	    end
	counter <= 0;
      end
    else
      counter <= counter-1;
    stx_o_tmp <= bit_out;
  endrule

  rule send_parity(enable && (tstate==STX_send_parity));
    if(counter==0)
      counter <= 5'b01111;
    else if(counter==1)
      begin
	counter <= 0;
	tstate <= STX_send_stop;
      end
    else
      counter <= counter-1;
    stx_o_tmp <= bit_out;
  endrule

  rule send_stop(enable && (tstate==STX_send_stop));
    if(counter==0)
      counter <= lc.uart_LC_SB==0   ? 5'b01101 : // 1 stop bit
                 lc.uart_LC_BITS==0 ? 5'b10101 : // 1.5 stop bits
				      5'b11101;  // 2 stop bits
    else if(counter==1)
      begin
	counter <= 0;
	tstate <= STX_idle;
	tx_fifo.deq;
      end
    else
      counter <= counter-1;
    stx_o_tmp <= 1;
  endrule
  
  method Action tx_char(Bit#(8) c);
    tx_fifo.enq(c);
  endmethod

  method Bool tx_buf_empty = tx_fifo_empty;

  method Action control(UART_LC_T lc_in, Bool enable_in);
    lc <= lc_in;
    enable <= enable_in;
  endmethod

  method bit output_stx = lc.uart_LC_BC==1 ? 0 : stx_o_tmp;  // handle break condition

endmodule


//////////////////////////////////////////////////////////////////////////////
// receiver

interface UART_receiver_ifc;
  method ActionValue#(RX_DATA_T) rx_char();
  (* always_ready, always_enabled *)
  method Bool timeout();
  (* always_ready, always_enabled *)
  method Action control(UART_LC_T lc_in, Bool enable_in);
  (* always_ready, always_enabled *)
  method Action input_srx(bit rx);
endinterface


module mkUART_receiver(UART_receiver_ifc);

  FIFOF#(RX_DATA_T)    rx_fifo <- mkLFIFOF;
  Reg#(bit)          rx_stable <- mkReg(1);
  Wire#(UART_LC_T)          lc <- mkBypassWire;
  Wire#(Bool)           enable <- mkBypassWire;
  Reg#(RX_state_T)      rstate <- mkReg(SRX_idle);
  Reg#(RX_state_T) last_rstate <- mkReg(SRX_idle);
  Reg#(UInt#(4))      rcounter <- mkReg(0);
  Reg#(UInt#(3))  rbit_counter <- mkReg(0);
  Reg#(Bit#(8))         rshift <- mkReg(0);
  Reg#(bit)            rparity <- mkReg(0);
  Reg#(bit)      rparity_error <- mkReg(0);
  Reg#(bit)     rframing_error <- mkReg(0);
  Reg#(bit)        rparity_xor <- mkReg(0);
  Reg#(UInt#(8))     counter_b <- mkReg(159);
  Reg#(UInt#(10))    counter_t <- mkReg(511);
  PulseWire   counter_t_preset <- mkPulseWireOR;
     
  Bool break_error = counter_b==0;
  
  rule monitor_state_for_debug(last_rstate != rstate);
    /*
     $write("%05t: UART RX state change ", $time);
    $write(fshow(last_rstate));
    $write(" -> ");
    $display(fshow(rstate));
     */
    last_rstate <= rstate;
  endrule
  
  (* no_implicit_conditions *)
  rule receive_status_counters;
    UInt#(10) toc_value;
    case ({lc.uart_LC_PE, lc.uart_LC_SB, lc.uart_LC_BITS})
      4'b0000: toc_value = 447; // 7 bits
      4'b0100: toc_value = 479; // 7.5 bits
      4'b0001,
      4'b1000: toc_value = 511; // 8 bits
      4'b1100: toc_value = 543; // 8.5 bits
      4'b0010,
      4'b0101,
      4'b1001: toc_value = 575; // 9 bits
      4'b0011,
      4'b0110,
      4'b1010,
      4'b1101: toc_value = 639; // 10 bits
      4'b0111,
      4'b1011,
      4'b1110: toc_value = 703; // 11 bits
      4'b1111: toc_value = 767; // 12 bits
      default: toc_value = 511; // 8 bits
    endcase
    
    UInt#(8) brc_value = truncate(toc_value>>2);  // break counter value
    
    if(rx_stable==1)
      counter_b <= brc_value;
    else if((counter_b!=0) && enable)
      counter_b <= counter_b-1;
    
    if(counter_t_preset)
      counter_t <= toc_value;
    else if(enable && (counter_t!=0))
      counter_t <= counter_t - 1;
  endrule
  
  // helper rule to decouple firing dependancies
  rule couter_t_preset_on_fifo_empty(!rx_fifo.notEmpty);
    counter_t_preset.send();
  endrule

  (* no_implicit_conditions *)
  rule idle(enable && (rstate==SRX_idle));
    rcounter <= 4'b1110;
    if((rx_stable==0) && !break_error)
      rstate <= SRX_rec_start;
  endrule

  rule rec_start(enable && (rstate==SRX_rec_start));
    if(rcounter==7)
      if(rx_stable==1) // no start bit
	rstate <= SRX_idle;
      else
	rstate <= SRX_rec_prepare;
    rcounter <= rcounter-1;
  endrule
  
  rule rec_prepare(enable && (rstate==SRX_rec_prepare));
    rbit_counter <= unpack(zeroExtend(lc.uart_LC_BITS) + 4);
    if(rcounter==0)
      begin
	rstate <= SRX_rec_bit;
	rcounter <= 4'b1110;
	rshift <= 0;
      end
    else
      rcounter <= rcounter-1;
  endrule
  
  rule rec_bit(enable && (rstate==SRX_rec_bit));
    if(rcounter==0)
      rstate <= SRX_end_bit;
    if(rcounter==7) // read the bit
      case(lc.uart_LC_BITS) // number of bits in a word
	0: rshift[4:0] <= {rx_stable, rshift[4:1]};
	1: rshift[5:0] <= {rx_stable, rshift[5:1]};
	2: rshift[6:0] <= {rx_stable, rshift[6:1]};
	3: rshift[7:0] <= {rx_stable, rshift[7:1]};
      endcase
    rcounter <= rcounter-1;
  endrule
  
  rule end_bit(enable && (rstate==SRX_end_bit));
    if(rbit_counter==0) // no more bits in the word
      begin
	rstate <= (lc.uart_LC_PE==1) ? SRX_rec_parity : SRX_rec_stop;
	rparity_error <= 0;
      end
    else
      rstate <= SRX_rec_bit;
    rbit_counter <= rbit_counter-1;
    rcounter <= rcounter-1;
  endrule
  
  rule rec_parity(enable && (rstate==SRX_rec_parity));
    if(rcounter == 7) // read parity
      begin
	rparity <= rx_stable;
	rstate <= SRX_ca_lc_parity;
	end
    rcounter <= rcounter-1;
  endrule
  
  rule calc_parity(enable && (rstate==SRX_ca_lc_parity));
    rparity_xor <= ^{rshift, rparity};
    rstate <= SRX_check_parity;
    rcounter <= rcounter-1;
  endrule

  rule check_parity(enable && (rstate==SRX_check_parity));
    case({lc.uart_LC_EP, lc.uart_LC_SP})
      2'b00: rparity_error <= ~rparity_xor;
      2'b01: rparity_error <= ~rparity;
      2'b10: rparity_error <= rparity_xor;
      2'b11: rparity_error <= rparity;
    endcase
    rcounter <= rcounter-1;
    rstate <= SRX_wait1;
  endrule
  
  rule wait1(enable && (rstate==SRX_wait1));
    if(rcounter==0)
      begin
	rcounter <= 4'b1110;
	rstate <= SRX_rec_stop;
      end
    else
      rcounter <= rcounter-1;
  endrule
  
  rule rec_stop(enable && (rstate==SRX_rec_stop));
    if(rcounter==7) // read the stop bit
      begin
	rframing_error <= ~rx_stable; // no framing error if stop bit = 1
	rstate <= SRX_push;
      end
    rcounter <= rcounter-1;
  endrule
  
  rule push(enable && (rstate==SRX_push));
    if((rx_stable==1) || break_error)
      begin
	rstate <= SRX_idle;
	if(break_error)
	  rx_fifo.enq(
	     RX_DATA_T{
		data: 8'b0,
		break_error: True,
		parity_error: True,
		framing_error: False
		}
	     );
	else
	  rx_fifo.enq(
	     RX_DATA_T{
		data: rshift,
		break_error: False,
		parity_error: rparity_error==1,
		framing_error: rframing_error==1
		}
	     );
	counter_t_preset.send;  // preset counter_t on an enq
      end
  endrule
  
  method ActionValue#(RX_DATA_T) rx_char();
    counter_t_preset.send;  // preset counter_t on a deq
    rx_fifo.deq;
    return rx_fifo.first;
  endmethod
  method Bool timeout() = counter_t==0;
  method Action control(UART_LC_T lc_in, Bool enable_in);
    lc <= lc_in;
    enable <= enable_in;
  endmethod
  method Action input_srx(bit rx);
    rx_stable <= rx;
  endmethod
endmodule


//////////////////////////////////////////////////////////////////////////////
// clocked RS (reset/set) flip-flow with reset dominating and edge triggering set

/*
(* always_ready, always_enabled *)
interface RS_ifc;
  method Action set;
  method Action reset;
  method Action enable(Bool en);
  method Bool state;
endinterface


module mkRS(RS_ifc);
  PulseWire        s <- mkPulseWire;
  PulseWire        r <- mkPulseWireOR;
  Wire#(Bool)      e <- mkBypassWire;
  Wire#(Bool) q_next <- mkBypassWire;
  Reg#(Bool)       q <- mkReg(False);
  Reg#(Bool)  s_prev <- mkReg(False);
  
  (* no_implicit_conditions *)
  rule handle_state_update;
    Bool s_rise = s && !s_prev;
    q_next <= e && !r && (s_rise || q);
    q <= q_next;
    s_prev <= s;
  endrule

  method Action set;    s.send();  endmethod
  method Action reset;  r.send();  endmethod
  method Bool   state   = q_next;
  method Action enable(Bool en);
    e <= en;
  endmethod
  
endmodule    
*/


(* always_ready, always_enabled *)
interface RS_ifc;
  method Action set;
  method Action reset;
  method Action posedge_set;
  method Action posedge_reset;
  method Bool state;
endinterface

module mkRS(RS_ifc);
  PulseWire        s <- mkPulseWireOR;
  PulseWire        r <- mkPulseWireOR;
  PulseWire   edge_s <- mkPulseWireOR;
  PulseWire   edge_r <- mkPulseWireOR;
  
  Reg#(Bool)       q <- mkReg(False);
  Reg#(Bool)  s_prev <- mkReg(False);
  Reg#(Bool)  r_prev <- mkReg(False);


  (* no_implicit_conditions *)
  rule handle_edges_history;
    s_prev <= s;
    r_prev <= r;
  endrule
  
  (* no_implicit_conditions *)
  rule handle_edges_set;
    if(edge_s && !s_prev) s.send;
    if(edge_r && !r_prev) r.send;
  endrule
  
  (* no_implicit_conditions *)
  rule handle_state_update;
    q <= !r && (q || s);
  endrule
  
  method Action set;           s.send();       endmethod
  method Action reset;         r.send();       endmethod
  method Action posedge_set;   edge_s.send();  endmethod
  method Action posedge_reset; edge_r.send();  endmethod
  method Bool   state          = q;
  
endmodule    


endpackage
