Notes on interface to Philips USB controller: ISP1761
=====================================================
Simon Moore, 24 Nov 2012


Testing
=======

Some basic testing has been done using a NIOS II based project.  It
gets as far as identifying USB devices, their speed, etc.


Files
=====

ISP1761_IF.v
- code provided by Terasic modified by SWM to be compatible with Qsys
- provides a simple AvalonMM to external tri-state bus for Philips
  chip

ISP1761_IF_hw.tcl
- TCL configuration for the above
- IMPORTANT: this includes bus timing information for the Philips part
  which is critical to it working correctly.


Pin Definitions
===============

Pin definitions are in:
ISP1761_IF_pins.qsf

The top-level Verilog pin definitions are:

//////////// 3-port High-Speed USB OTG //////////
output              [17:1]              OTG_A;
output                                  OTG_CS_n;
inout               [31:0]              OTG_D;
output                                  OTG_DC_DACK;
input                                   OTG_DC_DREQ;
input                                   OTG_DC_IRQ;
output                                  OTG_HC_DACK;
input                                   OTG_HC_DREQ;
input                                   OTG_HC_IRQ;
output                                  OTG_OE_n;
output                                  OTG_RESET_n;
output                                  OTG_WE_n;
