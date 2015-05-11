Notes on the files in this directory which provide functionality for a
reconfigurable clock source suitable for driving video output at
different resolutions.

Note - for further documentation see comments in the head of
video_pll_reconfig_avalonmm.sv and the Peripherals chapter of the
Cheri Users Guide.

Makefile
- simple Makefile to copy the video_pll_reconfig* files to
  ../qsys_ip/VideoPLL

Example Altera megafunction for a phased-locked loop (ALTPLL) for use
in the top-level Verilog of the project:
  video_pll_bb.v
  video_pll.mif
  video_pll.ppf
  video_pll.qip
  video_pll.v

Qsys memory-mapped peripheral and associated Altera megafunction
(ALTPLL_RECONFIG) which provides reconfiguration of the above PLL:
  video_pll_reconfig_avalonmm_hw.tcl
  video_pll_reconfig_avalonmm.sv
  video_pll_reconfig_bb.v
  video_pll_reconfig.qip
  video_pll_reconfig.v

