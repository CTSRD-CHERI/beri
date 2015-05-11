/*-
 * Copyright (c) 2012 Simon W. Moore
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
 *****************************************************************************

 Fan Control
 ===========

 WARNING - THIS PERIPHERAL APPEARS TO WORK CORRECTLY AT 50MHz BUT THE
 ALTERA COMPONENT THAT READS THE TEMPERATURE REPORTS A MINIMUM PULSE
 WIDTH ERROR.  THIS GOES AWAY IF THE MODULE IS CLOCKED AT 27MHz.
 
 This peripheral controls the FPGA fan based on the internal FPGA temperature
 sensor reading.  This has been tested on the DE4 board where there is no
 fan speed sensor.
 
 There is a read-only AvalonMM interface which has two 32-bit word aligned
 addresses:
   0 - the last temperature reading (32-bit signed number)
   1 - the power going to the fan in the range 0 to 255 where 0=off
       and 255=full power.  This roughly equates to fan speed and hence noise

 External conduit interfaces: 
 - the fan control (a pulse width modulated signal)
 - temperature information for two 7-segment displays
  
 ASSUMPTIONS:
 - the main clock is running at 50MHz
   - this is critical for the temp_sense megafunction
 - the target maximum FPGA temperature is 40 deg C (see targetTemperature)
 - the minimum fan speed is 8'b0110_0000 based on experimental testing of the
   fan stall speed

 Notes:
 
 - This uses the ALTTEMP megafunction which has been instantiated as
   temp_sense* and requires temp_sense.qip to be added to the Quartus
   project.
 
 - The input clock need to be 50MHz.  Any higher and the ALTTEMP megafunction
   will have its ADC clocked too high and the reading will be wrong.  I'm
   unsure what happens if the clock is slower, so don't do it!
 
 - Terasic provide an external ADC to read the temperature sensor but Altera
   indicates that this is probably only useful if the whole FPGA is disabled
   whilst the temperature is taken, otherwise there is too much noise.  The
   internal sensor doesn't suffer from this problem.
 
 - The ALTTEMP MegaFunction only appears to do a new reading after it has
   been cleared, so the "optional" clear (clr) input seems essential.
 
 - The ALTTEMP manual devotes a whole page to a partially completed table
   mapping ADC values read to degrees Centigrade.  But if you plot the data
   it becomes obvious that the temperature is just the ADC value -128.
 
 - To test I found it helpful to set the targetTemperature to 30 degC since
   the FPGA easily gets up to this temperature but with the design I was
   using (which exercised the serial links) it didn't get hot enough to need
   the fan at full speed but it had to be more than the minimum.
 
 - The fan is always run at a minimum speed which I experimentally
   determined to be the minimum where the fan motor didn't stall.  But this
   experiment was only conducted on two fans so there is a chance that we
   will find a fan which requires a higher minimum.  This is not too big an
   issues since if the FPGA starts to get hot, the fan speed with always
   increase and eventially the fan will turn on.
 
 *****************************************************************************/


package FanControl;

import GetPut::*;
import ClientServer::*;
import Avalon2ClientServer::*;


// type of 7-segment hex display bits
typedef Bit#(7) HexLEDT;


// conduit interfaces to export
(* always_ready, always_enabled *)
interface FanControlConduit;
  method Bool    fan_on_pwm;
  method HexLEDT temp_upper_seg_n;
  method HexLEDT temp_lower_seg_n;
endinterface


// top-level interface
(* always_ready, always_enabled *)
interface FanControl;
  interface AvalonSlaveBEIfc#(1) avs;
  interface FanControlConduit    coe;
endinterface


// helper function which converts 4-bits into 7-segment hex representation
function HexLEDT hex2leds(Bit#(4) hexval);
  case(hexval)
    4'h0: return 7'b0111111;
    4'h1: return 7'b0000110;
    4'h2: return 7'b1011011;
    4'h3: return 7'b1001111;
    4'h4: return 7'b1100110;
    4'h5: return 7'b1101101;
    4'h6: return 7'b1111101;
    4'h7: return 7'b0000111;           
    4'h8: return 7'b1111111;           
    4'h9: return 7'b1100111;           
    4'ha: return 7'b1110111;           
    4'hb: return 7'b1111100;           
    4'hc: return 7'b1011000;           
    4'hd: return 7'b1011110;           
    4'he: return 7'b1111001;           
    4'hf: return 7'b1110001;           
  endcase
endfunction


interface TempSense;
  method Action  run();
  method Action  clear();
  method Bool    done;
  method Bit#(8) adc_val;
endinterface

import "BVI" temp_sense =
module mkTempSense(TempSense);
  default_clock clk(clk, (*unused*) clk_gate);
  default_reset no_reset;
  method run()
    enable (ce);
    schedule (run) C (run);
  method clear()
    enable (clr);
    schedule (clear) C (clear);
    schedule (run)   CF (clear);
  method tsdcaldone done;
    schedule (done) CF (done);
    schedule (done) CF (adc_val);
  method tsdcalo    adc_val;
    schedule (adc_val) CF (adc_val);
    schedule (adc_val) CF (done);
    schedule (run,clear) CF (done,adc_val);
endmodule


(* synthesize,
   reset_prefix = "csi_clockreset_reset_n",
   clock_prefix = "csi_clockreset_clk" *)
module mkFanControl50MHz(FanControl);
  
  Int#(8) targetTemperature = 40;             // default target temperature is 40 degC
  Bit#(8) fanMinSpeed       = 8'b0110_0000;   // minimum fan speed for PWM controller
  
  Reg#(Bit#(19))       timer <- mkReg(0);     // determines temperature sensor polling interval, etc.
  Reg#(Bit#(8))     fanSpeed <- mkReg(~0);    // fan pulse-width modulator (PWM) value
  Reg#(Bool)      fanPowerOn <- mkReg(True);
  Reg#(Int#(8))  currentTemp <- mkReg(127);
  Reg#(Bool)   runTempSensor <- mkReg(False);
  Reg#(Bool) done_metastable <- mkReg(False);
  Reg#(Bool)       done_sync <- mkReg(False);
  TempSense           sensor <- mkTempSense;
  
  AvalonSlave2ClientBEIfc#(1)
                avalon_slave <- mkAvalonSlave2ClientBE;

  (* no_implicit_conditions *)
  rule fan_controller (True);
    // synchronise sensor done signal
    done_metastable <= sensor.done();
    done_sync <= done_metastable;

    timer <= timer+1;
    Bool trigger_reading_seq = timer < 4;

    if(runTempSensor)
      sensor.run();
    
    if(trigger_reading_seq)
      begin
	sensor.clear();
        runTempSensor <= True;
      end
    else if(done_sync)
      begin
	runTempSensor <= False;
	currentTemp <= unpack(sensor.adc_val()) + (-128);
      end

    Bit#(8)  fanTimer = timer[7:0]; // share counter bits
    fanPowerOn <= (fanTimer <= fanSpeed); // PWM the fan
    if(timer == ~0)
      begin
	let nextFanSpeed = fanSpeed;
	if((currentTemp > targetTemperature) && (fanSpeed != ~0))
	  nextFanSpeed = nextFanSpeed + 1;
	if((currentTemp < targetTemperature) && (fanSpeed > fanMinSpeed))
	  nextFanSpeed = nextFanSpeed - 1;
	if(nextFanSpeed < fanMinSpeed)
	  nextFanSpeed = fanMinSpeed;
	fanSpeed <= nextFanSpeed;
      end
  endrule

  
  // handle the AvalonMM slave interface to allow status to be read
  rule avalon_slave_reads;
    let req <- avalon_slave.client.request.get();
    ReturnedDataT rtn = tagged Invalid;
    if(req.rw == MemRead) // ignore writes
      case(req.addr)
	0 : begin
	      Int#(32) currentTemp32 = extend(currentTemp);
	      rtn = tagged Valid unpack(pack(currentTemp32));
	    end
	1 : rtn = tagged Valid extend(unpack(fanSpeed));
      endcase
    avalon_slave.client.response.put(rtn);
  endrule
  
  Bit#(4) tempUnits = pack(truncate(currentTemp % 10));
  Bit#(4) tempTens  = pack(truncate(currentTemp / 10));
  
  interface avs = avalon_slave.avs;
  interface FanControlConduit coe;
    method Bool    fan_on_pwm;       return fanPowerOn;               endmethod
    method HexLEDT temp_upper_seg_n; return ~hex2leds(tempTens); endmethod
    method HexLEDT temp_lower_seg_n; return ~hex2leds(tempUnits); endmethod
  endinterface    
endmodule



endpackage
