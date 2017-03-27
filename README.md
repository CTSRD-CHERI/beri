BERI Processor 'bigarreau' release 1  
=================================

24 March 2017

Welcome to the BERI Processor release!

BERI ('Bluespec Extensible RISC Implementation') is an FPGA soft-core RISC
processor implementing a 64-bit MIPS-like ISA and providing a large number
of system peripherals.  BERI is capable of running FreeBSD version 10.0
onwards.  BERI is written in Bluespec System Verilog.

BERI is derived from a research project called CHERI ('Capability
Hardware Enhanced RISC Instructions') at SRI International and the
University of Cambridge.  CHERI adds some extra features to the BERI core
which can be selected with build flags - it also means much of the source
tree refer to 'cheri' but are equally relevant to 'beri'.  CHERI extends
the ISA to include a 'capability coprocessor' supporting fine-grained
in-address-space memory protection and scalable compartmentalisation.
CHERI's ISA extensions and features are considered extremely experimental
and are an active target of continuing research.  Documentation for these
ISA extensions may be found in the CHERI Architecture Document.

The primary BERI release targets the DE4 FPGA board from Terasic [1] which
contains an Altera Stratix 4 GX230 FPGA.  A port to Xilinx FPGAs as part of
the NetFPGA 10G initiative is under way, but is not included in the current
release.

[1] http://de4.terasic.com/

This release includes targets for simulation of BERI1/2 and CHERI1/2
processors, and files for FPGA synthesis for the DE4 board.


Preliminaries
=============

To build BERI you will need a Bluespec licence: if you are an academic
institution this is available under the Bluespec University Program [2].

 [2] http://bluespec.com/university-program.html

Further instructions for configuring your environment and building can be
found in the BERI Hardware Reference (see below).

Instructions for building and booting FreeBSD on BERI can be found in the
BERI Software Reference.  The CHERI Users' Guide describes the tools
necessary to use the CHERI capability extensions.


Source-code structure
=====================

The BERI/CHERI source tree is organised into the following structure:

Path in tree           | Function
-----------------------|--------------------------------------------------
cheri/trunk/           | The CHERI1 CPU design
cheri/trunk/sw/        | Software to run bare-metal, when not using the
                       | miniboot primary bootloader
cherilibs/trunk/       | Common libraries across CHERI1/CHERI2; peripherals
cheribsd/trunk/        | Miniboot, simulation boot loader
cheritest/trunk/       | The CHERI instruction set testsuite


Software
========

A small 'hello world' test program may be found in cheri/trunk/sw/.  We
separately distribute the BERI ISA-level test suite ('cheritest') and
distributions of FreeBSD/beri and CheriBSD suitable to run on the BERI and
CHERI designs.  The former is an essentially unmodified version of FreeBSD,
as platform-support code and device drivers have been upstreamed.  The
latter depends on experimental kernel, compiler, and userspace changes and
is likely suitable only for those interested in capability-system research
rather than a general-purpose FPGA soft-core processor.


Documentation
=============

We have separately distributed the following documents for BERI/CHERI users:

Document                                | Description
----------------------------------------|--------------------------------------
CHERI Documentation Roadmap             | Guide to other documents  
BERI Hardware Reference                 | BERI hardware documentation, testing  
BERI Software Reference                 | FreeBSD on BERI (and related topics)  
CHERI Instruction-set Architecture      | The CHERI security model and ISA  
CHERI User's Guide                      | CHERI-specific software reference  

These can be downloaded via links from  
  http://www.beri-cpu.org/


License
=======

BERI is licensed under the BERI Hardware-Software licence.  See the BERI
Open Systems CIC website for more information:

  http://www.beri-open-systems.org/

A copy of the license has also been included with this distribution.  If you
submit patches to BERI, we will ask that you (and likely also your employing
institution) sign and return BERI contribution agreements.


More information
================

Further information is available on the BERI website:

  http://www.beri-cpu.org/
