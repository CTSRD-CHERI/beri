#!/usr/bin/perl
#-
# Copyright (c) 2012 Simon W. Moore
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for
# additional information regarding copyright ownership.  BERI licenses this
# file to you under the BERI Hardware-Software License, Version 1.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at:
#
#   http://www.beri-open-systems.org/legal/license-1-0.txt
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
# @BERI_LICENSE_HEADER_END@
#

##############################################################################
# swmcp.pl
# ========
# Simon Moore, May 2012
#
# Quick hack by Simon Moore to send a file over a nios2-terminal
# to a CHERI processor.
#
# Before using this script, ensure that you are logged into the terminal
# and that the nios2-terminal has then been killed.  uuencode/uudecode
# are used to ensure no control characters are sent over the link.
# 
# Note: the $timeout value represents the number of read retries to
# perform before we believe the buffer is cleared.  This is an ugly hack
# and the value may need to be changed to suite your system.

use strict;
use IPC::Open2;
use Fcntl;


my $timeout=5000000;

($#ARGV==0) or die "Usage: swmcp file_to_send";

my $file=$ARGV[0];

local (*Reader, *Writer);
my $pid = open2(\*Reader, \*Writer, "nios2-terminal -q --instance 1");
my $bitbucket;
my $flags;
fcntl(Reader, F_GETFL, $flags) || die $!;
$flags |= O_NONBLOCK;
fcntl(Reader, F_SETFL, $flags) || die $!;
print "nios2-terminal started pid=",$pid,"\n";

flush_nios_terminal();
print Writer "uudecode\n";
flush_nios_terminal();

open(FIN,"uuencode $file $file |") or die $!;
while(<FIN>) {
    print Writer $_;
    do {
	chomp($bitbucket = <Reader>);
    } while($bitbucket ne "");
}
close(FIN);
&flush_nios_terminal();
print Writer "md5 $file\n";
my $j;
my $remote_md5;
my $local_md5;
($local_md5)=split(/ /,`md5sum $file`);
do {
    chomp($remote_md5 = <Reader>);
} while(index($remote_md5,"MD5")<0);
($bitbucket,$remote_md5) = split(/ = /,$remote_md5);
$remote_md5 =~ s/ //g;
$local_md5 =~ s/ //g;
print "local  md5 = ",$local_md5,"\n";
print "remote md5 = ",$remote_md5,"\n";
if($local_md5==$remote_md5) {
    print "PASSED\n"
} else {
    print "FAILED\n";
}
close Writer;
close Reader;
`kill $pid`;
waitpid($pid, 0);
exit;


sub display_nios_terminal
{
    my $k;
    my $j;
    my $rtn;
    do {
	for($j=$timeout,$rtn=""; ($j>0) && ($rtn eq ""); $j--) {
	    chomp($rtn=<Reader>);
	}
	if($j>0) {
	    print ": ",$rtn,"\n";
	}
    } while($j>0);
}


sub flush_nios_terminal
{
    my $j;
    my $rtn;
    do {
	for($j=$timeout,$rtn=""; ($j>0) && ($rtn eq ""); $j--) {
	    chomp($rtn=<Reader>);
	}
    } while($j>0);
}
