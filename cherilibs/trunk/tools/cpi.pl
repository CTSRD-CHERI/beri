#-
# Copyright (c) 2012 Jonathan Woodruff
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

use strict;

open FILE, "<", $ARGV[0] or die $!;
my $cycles=0;
my $instructions=0;
my $lines=0;
my @delays;
my $totalDelay;
my $clusterCycles;
my $clusterInstructions;
my $percent;
my $i;
my $line;
my $cpi;
my $branchhits;
my $branchmisses;
my $jumphits;
my $jumpmisses;
my $il1hits;
my $il1misses;
my $l1Rhits;
my $l1Rmisses;
my $l1Whits;
my $l1Wmisses;
my $l2Rhits;
my $l2Rmisses;
my $l2Whits;
my $l2Wmisses;
my $flushes;
my $quanta;
my $count;

print "\t1\t2\t3\t4\t5\t6\t7\t8\t9\t10\t\+\n";

while (<FILE>) {
  $line = $_;
  if ($line =~ /(\d+) dead cycles/) {
  	$cycles += $1;
	  $clusterCycles += $1;
  	$delays[$1] += $1;
  	$totalDelay += $1;
  }
  if ($line =~ /inst +\d+/) {
  	$cycles += 1;
	  $clusterCycles += 1;
  	$instructions += 1;
	  $clusterInstructions += 1;
  }
  if ($line =~ /\[\>BH/) {
  	$branchhits += 1;
  }
  if ($line =~ /\[\>BM/) {
  	$branchmisses += 1;
  }
  if ($line =~ /\[\>RH/) {
  	$jumphits += 1;
  }
  if ($line =~ /\[\>RM/) {
  	$jumpmisses += 1;
  }
  if ($line =~ /\[\$IL1H/) {
  	$il1hits += 1;
  }
  if ($line =~ /\[\$IL1M/) {
  	$il1misses += 1;
  }
  if ($line =~ /\[\$DL1RH/) {
        $l1Rhits += 1;
  }
  if ($line =~ /\[\$DL1RM/) {
        $l1Rmisses += 1;
  }
  if ($line =~ /\[\$DL1WH/) {
        $l1Whits += 1;
  }
  if ($line =~ /\[\$DL1WM/) {
        $l1Wmisses += 1;
  }
  if ($line =~ /\$L2RH/) {
  	$l2Rhits += 1;
  }
  if ($line =~ /\$L2RM/) {
  	$l2Rmisses += 1;
  }
  if ($line =~ /\$L2WH/) {
        $l2Whits += 1;
  }
  if ($line =~ /\$L2WM/) {
        $l2Wmisses += 1;
  }
  if ($line =~ /Flush/) {
  	$flushes += 1;
  }
  if ($instructions%4000000 == 0 && $instructions != 0) {
    $quanta += 1;
    print $quanta."\t";
  	for ($i=1; $i<=10; $i+=1) {
  		if ($delays[$i] != 0) {$percent = sprintf("%2.3f", 100*$delays[$i]/$totalDelay);}
  		else {$percent = 0;}
  		print $percent."\t";
  		$delays[$i]=0;
  	}
  	foreach (@delays) {
  		$i += $_;
  		$_=0;
  	}
    if ($totalDelay != 0) {$percent = sprintf("%2.3f", 100*$i/$totalDelay);}
    else {$percent = 0;}
    print $percent;
    if ($branchhits + $branchmisses != 0) {
      $cpi = sprintf("%2.3f", 100*$branchhits/($branchhits + $branchmisses));
      $count = sprintf("%3.0d", ($branchhits + $branchmisses)/1000);
      print "\tbr:".$cpi."(".$count.")";
    }
    if ($jumphits + $jumpmisses != 0) {
      $cpi = sprintf("%2.3f", 100*$jumphits/($jumphits + $jumpmisses));
      $count = sprintf("%3.0d", ($jumphits + $jumpmisses)/1000);
      print "\tjr:".$cpi."(".$count.")";
    }
    if ($il1hits + $il1misses != 0) {
      $cpi = sprintf("%2.3f", 100*$il1hits/($il1hits + $il1misses));
      $count = sprintf("%3.0d", ($il1hits + $il1misses)/1000);
      print "\tIL1:".$cpi."(".$count.")";
    }
    if ($l1Rhits + $l1Rmisses != 0) {
      $cpi = sprintf("%2.3f", 100*$l1Rhits/($l1Rhits + $l1Rmisses));
      $count = sprintf("%3.0d", ($l1Rhits + $l1Rmisses)/1000);
      print "\tL1R:".$cpi."(".$count.")";
    }
    if ($l1Whits + $l1Wmisses != 0) {
      $cpi = sprintf("%2.3f", 100*$l1Whits/($l1Whits + $l1Wmisses));
      $count = sprintf("%3.0d", ($l1Whits + $l1Wmisses)/1000);
      print "\tL1W:".$cpi."(".$count.")";
    }
    if ($l2Rhits + $l2Rmisses != 0) {
      $cpi = sprintf("%2.3f", 100*$l2Rhits/($l2Rhits + $l2Rmisses));
      $count = sprintf("%3.0d", ($l2Rhits + $l2Rmisses)/1000);
      print "\tL2R:".$cpi."(".$count.")";
    }
    if ($l2Whits + $l2Wmisses != 0) {
      $cpi = sprintf("%2.3f", 100*$l2Whits/($l2Whits + $l2Wmisses));
      $count = sprintf("%3.0d", ($l2Whits + $l2Wmisses)/1000);
      print "\tL2W:".$cpi."(".$count.")";
    }
    print "\tflushes:".$flushes;
    if ($clusterCycles != 0) {$cpi = sprintf("%2.3f", $clusterCycles/$clusterInstructions);}
    print "\tcpi:".$cpi;
    if ($cycles != 0) {$cpi = sprintf("%2.3f", $cycles/$instructions);}
    print "\t(".$cpi.")\n";
    $branchhits = $branchmisses = $jumphits = $jumpmisses = 0;
    $il1hits = $il1misses = $l1Rhits = $l1Rmisses = $l1Whits = $l1Wmisses = $l2Rhits = $l2Rmisses = $l2Whits = $l2Wmisses = 0;
    $flushes = 0;
    $totalDelay = 0;
    $clusterCycles = 0;
    $clusterInstructions = 0;
    $instructions += 1;
  }
}

$cpi = $cycles/$instructions;
print "CPI = ".$cpi."\n";
#$cpi = $misses/$branches;
#print "Branch miss rate = ".$cpi."\n";
