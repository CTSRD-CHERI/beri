#-
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2013 Philip Withnall
# Copyright (c) 2014 Robert N. M. Watson
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

 # Generate a Hex file containing version information for initializing a 
 # small ROM in a quartus project.
 
 proc cksum {bytes} {
	# Calculate Intel-hex CRC for list of bytes (usual numbers in hex format
	# but without prefixes like b|w|d|q)
	set sum 0
	foreach b $bytes {
	    incr sum 0x$b
	}
	set sum [expr {(1 + ~$sum) & 0xFF}] ;# bcb
	return $sum
}
 

# Generate 2, 8-nibble strings containing the (day, month & year), and 
# the (hour, minutes & seconds) of the build in binary coded decimal.
set versionDayMonthYear [ clock format [ clock seconds ] -format %d%m%Y ]
set versionHourMinutesSeconds "00"
append versionHourMinutesSeconds [ clock format [ clock seconds ] -format %H%M%S ]

puts "$versionHourMinutesSeconds\n"

# Get SVN version string. If it's 'exported', this user is using git-svn, so
# fall back to `git describe`. We should end up with an 8-character hex string.
set svnVersionString [exec svnversion .]
if {$svnVersionString == "exported"} {
	set svnVersionString [exec git describe --always]
}
if {$svnVersionString == ""} {
	set svnVersionString [exec cat svnversion.txt]
}
puts "$svnVersionString\n"
regexp {[[:xdigit:]]+} $svnVersionString svnVersionString
while {[string length $svnVersionString] < 8} {
	set svnVersionString [format "%s%s" "0" $svnVersionString]
}
puts "$svnVersionString\n"

# Get the host name, truncate to the first 8 characters in two sets of 4
# to match the 4-byte wide memory we will have.
set hostNameString	[exec hostname]
while {[string length $hostNameString] < 8} {
	set hostNameString [format "%s%s" "0" $hostNameString]
}
set hostNameString1	[string range $hostNameString 0 3]
set hostNameString2	[string range $hostNameString 4 7]
binary scan $hostNameString1 "H*" hostNameHex1
binary scan $hostNameString2 "H*" hostNameHex2
puts "$hostNameString1\n"
puts "$hostNameString2\n"

# Create output file
set romFileName "version.hex"
set romFile [open $romFileName "w"]

# Output the build date
set outStr "04000000$versionDayMonthYear"
puts $romFile [format ":%s%02X" $outStr [cksum [regexp -all -inline {..} $outStr]]]
set outStr "04000100$versionHourMinutesSeconds"
puts $romFile [format ":%s%02X" $outStr [cksum [regexp -all -inline {..} $outStr]]]
set outStr "04000200$svnVersionString"
puts $romFile [format ":%s%02X" $outStr [cksum [regexp -all -inline {..} $outStr]]]
set outStr "04000300$hostNameHex1"
puts $romFile [format ":%s%02X" $outStr [cksum [regexp -all -inline {..} $outStr]]]
set outStr "04000400$hostNameHex2"
puts $romFile [format ":%s%02X" $outStr [cksum [regexp -all -inline {..} $outStr]]]
puts $romFile ":00000001FF"
close $romFile
