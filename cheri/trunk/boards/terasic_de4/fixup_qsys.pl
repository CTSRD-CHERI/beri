#!/usr/bin/env perl

#-
# Copyright (c) 2015 A. Theodore Markettos
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

# Take an input Qsys file, and make some substitutions based on input parameters:
# Alter BERI to the name of the IP we're using,
# and adjust the timing for 4GB DIMMs if necessary


use strict;

if ($#ARGV != 3) {
 print "$#ARGV";
 print "usage: fixup_qsys.pl <dimm_size=1|4> <ip_name> <input_qsys_file> <output_qsys_file>\n";
 exit;
}

my $dimm =  $ARGV[0];
my $ip =    $ARGV[1];
my $infile = $ARGV[2];
my $outfile = $ARGV[3];

open(IN, $infile) or die $!;
my @input = <IN>;
close(IN);

my $done = 0;
for (@input)
{
 s/BERI/$ip/g;
 if ($dimm == 4)
 {
  # make sure each substitution is done at least once - if a bit isn't set then we missed that line
  s/parameter name="MEM_VENDOR" value="JEDEC"/parameter name="MEM_VENDOR" value="Micron"/g and $done |= 1;
  s/parameter name="TIMING_BOARD_DERATE_METHOD" value="AUTO"/parameter name="TIMING_BOARD_DERATE_METHOD" value="MANUAL"/g and $done |= 2;
  s/parameter name="TIMING_BOARD_TIS" value="0.0"/parameter name="TIMING_BOARD_TIS" value="0.375"/g and $done |= 4;
  s/parameter name="TIMING_BOARD_TIH" value="0.0"/parameter name="TIMING_BOARD_TIH" value="0.375"/g and $done |= 8;
  s/parameter name="TIMING_BOARD_TDS" value="0.0"/parameter name="TIMING_BOARD_TDS" value="0.248"/g and $done |= 16;
  s/parameter name="TIMING_BOARD_TDH" value="0.0"/parameter name="TIMING_BOARD_TDH" value="0.229"/g and $done |= 32;
  s/parameter name="TIMING_BOARD_ISI_METHOD" value="AUTO"/parameter name="TIMING_BOARD_ISI_METHOD" value="MANUAL"/g  and $done |= 64;
  s/parameter name="TIMING_BOARD_MAX_CK_DELAY" value="0.6"/parameter name="TIMING_BOARD_MAX_CK_DELAY" value="0.5"/g  and $done |= 128;
  s/parameter name="TIMING_BOARD_MAX_DQS_DELAY" value="0.6"/parameter name="TIMING_BOARD_MAX_DQS_DELAY" value="0.5"/g  and $done |= 256;
 }
}

if ($dimm == 4 && $done != 0x1ff)
{
 die "fixup_qsys.pl: Couldn't change memory parameters in Qsys file (flags=$done)";
}


open(OUT, ">$outfile") or die $!;
print OUT @input;
close(OUT);
exit;
