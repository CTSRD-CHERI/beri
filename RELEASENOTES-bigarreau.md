Release Notes for `bigarreau' BERI release
=======================================

This is the `bigarreau' release of the BERI/CHERI CPU, released March 2017.
This release is a version of the CPU which corresponds to vX.XX of 'Capability 
Hardware Enhanced RISC
Instructions: CHERI Instruction-set architecture', UCAM-CL-TR-XXX.
http://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-XXX.pdf
and vX.X of the 'Bluespec Extensible RISC Implementation: BERI Hardware
reference', UCAM-CL-TR-XXX
http://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-XXX.pdf

Full architectural changes are described in those documents.

The following additional changes are noted between the previous 
'arcina' (r17605) and this 'bigarreau' (r26681)  release:

cheri/
------
The caches have been improved and now default to 32KB set-associative L1 caches
and a 256KB 4-way L2 cache which are able to pass timing at 100MHz on the 
Stratix IV FPGA.  Multi-core coherence is functional (boots and runs some 
benchmarks) in the default configuration.

The CHERI extensions now optionally use a compressed 128-bit format. To support
this, we have added the CSetBounds instruction and removed IncBase and 
SetLength. These changes are reflected in updates to the Cheri architecture 
document.

cheritest/
----------
Add tests for compressed ISA and compression format.

XXX add more notes here

cheribsd/
---------
XXX add notes here


