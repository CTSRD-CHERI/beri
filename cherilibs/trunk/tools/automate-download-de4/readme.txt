These step* scripts are designed to automate the process of
configuring the FPGA on the Terasic DE4 board, downloading a kernel
image and starting up a nios2-terminal to view the console.

Note that these scripts should be copied to a directory (not in this
repository) which contains the FPGA and kernel images.  Then configure
"steps-local-config.sh" with your local paths and image names.

step{0,1,2,3} take you through the verious stages and steps-all.sh
runs them all in the right sequence.  step3-terminal-helper.sh is a
helper script for step3-resume-terminal.sh.

If the DE4's flash has already been programmed with an FPGA image and
a kernel image then just the following are needed:
  step1-socketserver.sh
  step3-resume-terminal.sh

-----------------------------------------------------------------------------

swmcp.pl is a hacked together Perl script to transfer files to CHERI
over a nios2-terminal.  uuencode/uudecode are used to ensure not
control characters are sent.  md5 is used to check the integrity.
Before using this script, first login to FreeBSD running on CHERI
and then kill the nios2-terminal.  I found it useful to use:
  watch -W ttyv0
so that the terminal output went to the MTL-LCD so that I could
see what was going on.


Simon Moore
8 May 2012
