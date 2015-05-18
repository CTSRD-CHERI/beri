Release Notes for `arcina' BERI release
=======================================

This is the `arcina' release of the BERI/CHERI CPU, released May 2015.
This release is a version of the CPU which corresponds to our ASPLOS and
IEEE Security and Privacy papers on the CHERI architecture:

Robert N. M. Watson, Jonathan Woodruff, Peter G. Neumann, Simon W. Moore,
Jonathan Anderson, David Chisnall, Nirav Dave, Brooks Davis, Khilan Gudka,
Ben Laurie, Steven J. Murdoch, Robert Norton, Michael Roe, Stacey Son, and
Munraj Vadera. CHERI: A Hybrid Capability-System Architecture for Scalable
Software Compartmentalization, Proceedings of the 36th IEEE Symposium on
Security and Privacy ("Oakland"), San Jose, California, USA, May 2015.

David Chisnall, Colin Rothwell, Brooks Davis, Robert N.M. Watson, Jonathan
Woodruff, Simon W. Moore, Peter G. Neumann and Michael Roe. Beyond the
PDP-11: Processor support for a memory-safe C abstract machine, Proceedings
of Architectural Support for Programming Languages and Operating Systems
(ASPLOS 2015), Istanbul, Turkey, March 2015.

This corresponds with v1.11 of 'Capability Hardware Enhanced RISC
Instructions: CHERI Instruction-set architecture', UCAM-CL-TR-864.
http://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-864.pdf
and v1.4 of the 'Bluespec Extensible RISC Implementation: BERI Hardware
reference', UCAM-CL-TR-868
http://www.cl.cam.ac.uk/techreports/UCAM-CL-TR-868.pdf

Full architectural changes are described in those documents.

The following additional changes are noted between the previous ('r13006')
and this 'arcina' release:

cheri/
------
Released files for FPGA synthesis.  This is enough to boot FreeBSD on a DE4
board, however some third party IP (eg SD card controller) has had to be
omitted for licensing reasons.  For storage we recommend using USB or NFS
root instead.

The memory subsystem has been rebuilt with a purpose-built AXI interface, a
new internal memory bus format, and new L2 and data caches.  The L2 cache
and data cache are now parametrizable in both size and associativity.  The
memory bus width is also parametrisable.

The CHERI extensions now support offsets in addition to base and length.
Branch-on-tag instructions and several others have been added in the
capability unit.  A few instructions, such as CSealCode and CSealData have
been merged, modified, or removed.  These changes are all reflected in the
updates to the Cheri architecture document.

cheri2/
-------
Update to latest CHERI ISA v3 (cursors, separate otype field)

Switched to reservation based approach for ll/sc -- no more forward
progress problems because of cache conflicts as ll/sc metadata is not
stored in cache

Cleanups for formal verification -- wires and ConfigRegs replaced by
EHR/CReg

Improved bsv schedule to increase IPC-- eliminate conflicts between
pipeline stages and enabled capability register forwarding

Improved timing by making SFIFO forward previous value from pipeline
register, not currently generated value

Improved streamtrace -- added support for memory ops and capability
instructions

Added binary streamtrace output straight from simulator (+btrace)
Implemented WAIT instruction so that threads can yield processor to other
hw threads (previously a nop)

cherilibs/trunk/tools/analyse_trace.py
--------------------------------------
New script for analysing binary stream trace files. Can print a detailed
trace annotated with disassembly  (--show) and symbol names from executable
file(s) (--elf); divide a trace file up into chunks based on start/stop PC
(--cut); or calculate statistics such as cycles, instructions and cache/TLB
footprint (--stats). See --help for all options. V2 streamtrace format
recommended (see below)

berictl
-------
Added v2 trace format for binary trace files which includes previously
missing fields (e.g. ASID, thread) and a header to identify the trace
format. Enabled by the -v2 option to the streamtrace -b command. Binary
trace format is independent of CHERI version (i.e. -2 option to berictl
before streamtrace sub-command when using cheri2).

Added support for JTAG Atlantic (-j option), an undocumented Altera library
that permits faster access to JTAG UART devices than via nios2-terminal
(loadbin now 2x to 5x faster depending on CPU).

cheritest/
----------
Add substantially more tests for multicore

cheribsd/
---------
Modified the build system to build one target at a time rather than both
BERI and CHERI.  This makes it easier to support more build types.

Support for USB root file systems.

Preliminary support for boot loaders.

Integrated Flat Device Tree (FDT) builds into the hardware and simulation.
This reduces the number of kernel variants.

Many small performance tweaks (reducing interrupt load, supporting fewer
SSH key types, etc)

A new "smoketest" file system and kernel to make it easier to check that
a build or simulation is working.

Errata:
DE4 mdroot kernels no longer fit on the DE4's flash due to kernel growth.


Outstanding security bug
========================
We are aware of the following bug in this release, which has been fixed in
SVN r18576 but the change has not yet passed through our release testing
process:

CUnseal did not bounds-check the second capability argument which authorizes
an unseal of a specified type. That is, a user possessing any capability to
a type space (i.e. permit_seal is set) could construct an arbitrary
out-of-bounds offset to describe any desired type and successfully unseal a
capability of that type

