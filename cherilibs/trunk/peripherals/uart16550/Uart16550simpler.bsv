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

package Uart16550simpler;

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
    else if(uart_rx.timeout) // TODO: uart_rx cannot figureout timeout since it also depends on rx buffer fill level>0 which is in this module, and also timing of CPU reads
      ti_int.posedge_set;
    
    // modem status interrupt
    //  - note: also reset by reading modem status
    if(!ier.uart_IE_MS)
      ms_int.reset;
    else if({msr.uart_MS_DCTS, msr.uart_MS_DDSR, msr.uart_MS_TERI, msr.uart_MS_DDCD} != 0)
      ms_int.posedge_set;
  endrule
  
  (* no_implicit_conditions *)
  rule forward_lc_enable;
    uart_tx.control(lcr, dl);
    uart_rx.control(lcr, dl);
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
//
function bit calculate_parity(Bit#(8) data, UART_LC_T lc);
  bit parity_xor;
  bit parity;
  case(lc.uart_LC_BITS) // calculate parity bits based on bit width
          0: parity_xor = ^data[4:0];
          1: parity_xor = ^data[5:0];
          2: parity_xor = ^data[6:0];
    default: parity_xor = ^data[7:0];
  endcase
  case({lc.uart_LC_EP, lc.uart_LC_SP})
      2'b00: parity = ~parity_xor;
      2'b01: parity = 1;
      2'b10: parity = parity_xor;
    default: parity = 0;
  endcase
  return parity;
endfunction


//////////////////////////////////////////////////////////////////////////////
// transmitter (simpler version)

interface UART_transmitter_ifc;
  method Action tx_char(Bit#(8) c);
  (* always_ready, always_enabled *)
  method Bool tx_buf_empty;
  (* always_ready, always_enabled *)
  method Action control(UART_LC_T lc_in, Bit#(16) dl_in);
  (* always_ready, always_enabled *)
  method bit output_stx;
endinterface


module mkUART_transmitter(UART_transmitter_ifc);

  Reg#(Bit#(12))  tx_data <- mkReg(~0);
  Reg#(Bit#(12))  tx_mask <- mkReg(0);
  Wire#(UART_LC_T)     lc <- mkBypassWire;
  Wire#(Bit#(16))      dl <- mkBypassWire; // delay counter bound
  Reg#(Bit#(20))      dtx <- mkReg(0);     // delay counter for tx
  Reg#(Bool)       enable <- mkBypassWire;

  Bit#(20) dtx_max = extend(dl)*16-1;
  
  rule debug((dtx==dtx_max) && (lsb(tx_mask)==1));
    $display("%05t: tx bit = %1d", $time, lsb(tx_data));
  endrule
  
  rule shift_out((tx_mask!=0) && enable);
    if(dtx==0)
      begin
	tx_data <= {1'b1, tx_data[11:1]};
	tx_mask <= {1'b0, tx_mask[11:1]};
	dtx <= lsb(tx_mask)==1 ? dtx_max : 0;
      end
    else
      dtx <= dtx-1;
  endrule

  method Action tx_char(Bit#(8) c) if (tx_mask==0);
    Bit#(12) data = {3'b1,c,1'b0};
    Bit#(12) mask = {6'b000000,6'b111111};
    Bit#(3) ending;
    Bit#(3) maskend;
    Bit#(1) parity = calculate_parity(c, lc);
    if(lc.uart_LC_PE==1) // parity enable
      begin
	ending = {2'b11, parity};
	maskend = {lc.uart_LC_SB, 2'b11}; // stop bit (always 1 or 2, 1.5 not implemented)
      end
    else
      begin
	ending = 3'b111;
	maskend = {1'b0,lc.uart_LC_SB,1'b1}; // stop bit (always 1 or 2, 1.5 not implemented)
      end
    case(lc.uart_LC_BITS)
       0:       begin data[ 8:6] = ending;  mask[ 8:6]=maskend; end
       1:       begin data[ 9:7] = ending;  mask[ 9:6]={maskend,1'b1}; end
       2:       begin data[10:8] = ending;  mask[10:6]={maskend,2'b11}; end
       default: begin data[11:9] = ending;  mask[11:6]={maskend,3'b111}; end
    endcase
    tx_data <= data;
    tx_mask <= mask;
    dtx <= dtx_max;
    $display("%05t: ----------------------------------------------------------------------",$time);
  endmethod

  method Bool tx_buf_empty = (tx_mask==0);

  method Action control(UART_LC_T lc_in, Bit#(16) dl_in);
    lc <= lc_in;
    dl <= dl_in;
    enable <= dl_in != 0;
  endmethod

  method bit output_stx = lc.uart_LC_BC==1 ? 0 : lsb(tx_data);  // handle break condition

endmodule


//////////////////////////////////////////////////////////////////////////////
// receiver

interface UART_receiver_ifc;
  method ActionValue#(RX_DATA_T) rx_char();
  (* always_ready, always_enabled *)
  method Bool timeout();
  (* always_ready, always_enabled *)
  method Action control(UART_LC_T lc_in, Bit#(16) dl_in);
  (* always_ready, always_enabled *)
  method Action input_srx(bit rx);
endinterface


module mkUART_receiver(UART_receiver_ifc);

  Reg#(bit)      rx_metastable <- mkReg(1);
  Reg#(bit)          rx_stable <- mkReg(1);
  FIFOF#(RX_DATA_T)    rx_fifo <- mkLFIFOF;
  Wire#(UART_LC_T)          lc <- mkBypassWire;
  Wire#(Bit#(16))           dl <- mkBypassWire; // delay counter bound
  Reg#(Bit#(20))           drx <- mkReg(0);     // delay counter for rx
  Wire#(Bool)           enable <- mkBypassWire;
  Reg#(UInt#(4))   num_bits_rx <- mkReg(0);
  Reg#(UInt#(3))  num_bits_adj <- mkReg(0);
  Reg#(Bit#(11))       data_rx <- mkReg(0);
  
  Bit#(20) drx_max = extend(dl)*16-1;

  rule spot_start_bit (enable && (num_bits_rx==0) && (num_bits_adj==0) && (rx_stable==0));
    // number_of_bits = start_bit + character_width + optional_parity_bit + stop_bit
    UInt#(4) nb = 1 + (extend(unpack(lc.uart_LC_BITS))+5) + extend(unpack(lc.uart_LC_PE)) + 1;
    num_bits_rx <= nb+1;
    $display("%05t: spot_start_bit - num_bits_rx=%1d", $time, nb+1);
    num_bits_adj <= truncate(11-nb);
    drx <= drx_max/2; // sample at mid bit position
  endrule
  
  rule shift_in_bits(num_bits_rx>1);
    if(drx==0)
      begin
	data_rx <= {rx_stable,data_rx[10:1]};
	num_bits_rx <= num_bits_rx-1;
	drx <= drx_max;
	$display("%05t:              rx bit = %d", $time, rx_stable);
      end
    else
      drx <= drx-1;
  endrule
  
  // align bits where the number of bits in a character < 8 and/or no-parity
  rule align_data_rx_bits((num_bits_rx==1) && (num_bits_adj>0));
    if(num_bits_adj > 1)
      begin
	data_rx <= data_rx>>2;
	num_bits_adj <= num_bits_adj-2;
      end
    else
      begin
	data_rx <= data_rx>>1;
	num_bits_adj <= num_bits_adj-1;
      end
  endrule
  
  rule finish_rx((num_bits_rx==1) && (num_bits_adj==0));
    Bit#(8) data;
    Bit#(1) parity;
    Bit#(1) stop;
    Bit#(1) start = data_rx[0];
    Bit#(2) ending;
    case(lc.uart_LC_BITS)
      0:       begin data=extend(data_rx[5:1]); ending=data_rx[ 7:6]; end
      1:       begin data=extend(data_rx[6:1]); ending=data_rx[ 8:7]; end
      2:       begin data=extend(data_rx[7:1]); ending=data_rx[ 9:8]; end
      default: begin data=extend(data_rx[8:1]); ending=data_rx[10:9]; end
    endcase
    parity = lc.uart_LC_PE==1 ? ending[0] : 0;
    stop = ending[lc.uart_LC_PE];
    rx_fifo.enq(RX_DATA_T{
       data: data,
       break_error:    data_rx == 0, // break error if no 1's sent (not even a stop bit)
       parity_error:   parity==calculate_parity(data_rx[8:1], lc),
       framing_error:  (start==1) || (stop==0)
       });
    num_bits_rx <= 0;
  endrule

  method ActionValue#(RX_DATA_T) rx_char();
    rx_fifo.deq;
    return rx_fifo.first;
  endmethod
  method Bool timeout() = False;   // counter_t==0;  --- TODO: FIXME!!!!!!!!!
  method Action control(UART_LC_T lc_in, Bit#(16) dl_in);
    lc <= lc_in;
    dl <= dl_in;
    enable <= dl_in != 0;
  endmethod
  method Action input_srx(bit rx);
    rx_metastable <= rx;
    rx_stable <= rx_metastable;
  endmethod
endmodule


//////////////////////////////////////////////////////////////////////////////
// clocked RS (reset/set) flip-flow with reset dominating and edge triggering set

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
