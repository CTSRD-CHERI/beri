// The MIT License (MIT)
//
// Copyright (c) 2014 Paulo Matias
// Copyright (c) 2016 A. Theodore Markettos
// 
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import FIFOF::*;
import GetPut::*;
export GetPut::*;

export JtagWord(..);
export AlteraJtagUart(..);
//export AlteraJtagUartFIFO(..);
export mkAlteraJtagUart;
//export mkAlteraJtagUartFIFO;

typedef Bit#(8) JtagWord;

interface AltJtagAtlantic;
    method Bool can_write_next_cycle();
    method Action write(JtagWord data);
    method Action ask_read();
    method JtagWord read();
endinterface

import "BVI" alt_jtag_atlantic =
    module mkAltJtagAtlantic#(Integer log2rx, Integer log2tx, Bit#(8) sld_instance, Integer instance_auto) (AltJtagAtlantic);
        parameter INSTANCE_ID = sld_instance;
        // the parameters below use the inverse notation of ours
        parameter LOG2_RXFIFO_DEPTH = log2tx;  // from HW to JTAG
        parameter LOG2_TXFIFO_DEPTH = log2rx;  // from JTAG to HW
        parameter SLD_AUTO_INSTANCE_INDEX = (instance_auto==0) ? "NO" : "YES";
        
        method r_ena can_write_next_cycle();
        method write(r_dat) enable(r_val);
        method ask_read() enable(t_dav);
        method t_dat read() ready(t_ena);

        default_clock clk(clk, (*unused*)GATE);
        default_reset rst(rst_n);

        schedule (can_write_next_cycle) CF (write);
        schedule (can_write_next_cycle) CF (ask_read);
        schedule (can_write_next_cycle) CF (read);
        schedule (can_write_next_cycle) CF (can_write_next_cycle);
        schedule (write) CF (read);
        schedule (write) CF (ask_read);
        schedule (write) C (write);
        schedule (ask_read) C (ask_read);
        schedule (ask_read) CF (read);
        schedule (read) CF (read);
    endmodule

interface AlteraJtagUart;
    interface Put#(JtagWord) tx;
    interface Get#(JtagWord) rx;
endinterface

module mkAlteraJtagUart#(Integer log2rx, Integer log2tx, Bit#(8) sld_instance, Integer instance_auto) (AlteraJtagUart);
    AltJtagAtlantic atlantic <- mkAltJtagAtlantic(log2rx, log2tx, sld_instance, instance_auto);
    FIFOF#(JtagWord) rxfifo <- mkSizedFIFOF(2**log2rx);
    FIFOF#(JtagWord) txfifo <- mkSizedFIFOF(2**log2tx);
    Reg#(Bool) can_tx <- mkReg(False);

    rule ask_tx;
        can_tx <= atlantic.can_write_next_cycle;
    endrule
    rule do_tx(can_tx);
        atlantic.write(txfifo.first);
        txfifo.deq;
    endrule
    rule ask_rx(rxfifo.notFull);
        atlantic.ask_read();
    endrule
    rule do_rx;
        rxfifo.enq(atlantic.read());
    endrule

    interface Put tx = toPut(txfifo);
    interface Get rx = toGet(rxfifo);
endmodule
/*
interface AlteraJtagUartFIFO;
    interface FIFOF#(JtagWord) tx;
    interface FIFOF#(JtagWord) rx;
endinterface

module mkAlteraJtagUartFIFO#(Integer log2rx, Integer log2tx, Integer sld_instance) (AlteraJtagUartFIFO);
    AltJtagAtlantic atlantic <- mkAltJtagAtlantic(log2rx, log2tx, sld_instance);
    FIFOF#(JtagWord) rxfifo <- mkSizedFIFOF(2**log2rx);
    FIFOF#(JtagWord) txfifo <- mkSizedFIFOF(2**log2tx);
    Reg#(Bool) can_tx <- mkReg(False);

    rule ask_tx;
        can_tx <= atlantic.can_write_next_cycle;
    endrule
    rule do_tx(can_tx);
        atlantic.write(txfifo.first);
        txfifo.deq;
    endrule
    rule ask_rx(rxfifo.notFull);
        atlantic.ask_read();
    endrule
    rule do_rx;
        rxfifo.enq(atlantic.read());
    endrule

    interface FIFOF tx = txfifo;
    interface FIFOF rx = rxfifo;
endmodule
*/
