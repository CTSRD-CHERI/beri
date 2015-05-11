#-
# Copyright (c) 2014 A. Theodore Markettos
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
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

# Script to extract interesting information out of TimeQuest as CSV files
# May cause timing analysis to be rerun
# Run this from TimeQuest thus:
# $ quartus_sta -t fmax.tcl
# appending arguments as described below

# four CSV files are generated
# fmax report: a CSV of all the fmax and restricted_fmax in the design
# slack report: a CSV of all the slack in the design
# fmax graph: a limited CSV designed for Jenkins graphing. One clock is selected
# slack graph: the same for slack. Works around limitations in Jenkins Plot plugin

# $voltage is the lower voltage of the two process corners - varies by family

if { $argc != 7 } {
  puts "Syntax: $argv0 <project name> <fmax report filename> <slack report filename> <fmax graph filename> <slack graph filename> <clock name of interest> <voltage>"
} else {
  set fmax_filename [lindex $argv 1]
  set slack_filename [lindex $argv 2]
  set fmax_graph_filename [lindex $argv 3]
  set slack_graph_filename [lindex $argv 4]
  set clock [lindex $argv 5]
  set voltage [lindex $argv 6]
  project_open [lindex $argv 0]
  create_timing_netlist -model slow -voltage $voltage -temperature 85
  read_sdc my_project.sdc
  update_timing_netlist

  set csvFmax [open $fmax_filename "w"]
  set graphFmax [open $fmax_graph_filename "w"]

  # Get fmax info
  set domain_list [get_clock_fmax_info]
  puts $csvFmax "# signal name, fmax, restricted_fmax"
  puts $graphFmax "# Clock Fmax, fmax, restricted_fmax"
  foreach domain $domain_list {
          set name [lindex $domain 0]
          set fmax [lindex $domain 1]
          set restricted_fmax [lindex $domain 2]

          puts $csvFmax "\"$name\",$fmax,$restricted_fmax"
          if {$name eq $clock} {
            puts $graphFmax "$name,$fmax,$restricted_fmax"
          }
  }

  close $csvFmax
  close $graphFmax

  set csvSlack [open $slack_filename "w"]
  set graphSlack [open $slack_graph_filename "w"]

  # Get clock domain summary object and extract slacks
  set modes [list "setup" "hold" "recovery" "removal" "mpw"]
  set modeslist [join $modes ","]
  puts $graphSlack "# Clock slack, $modeslist" 
  puts -nonewline $graphSlack "$clock"
  foreach mode $modes {
    set flag "-$mode"
    set domain_list [get_clock_domain_info $flag]
    puts $csvSlack "# mode, signal name, slack, keeper_tns, edge_tns"
    foreach domain $domain_list {
            set name [lindex $domain 0]
            set slack [lindex $domain 1]
            set keeper_tns [lindex $domain 2]
            set edge_tns [lindex $domain 3]

            puts $csvSlack "$mode,\"$name\",$slack,$keeper_tns,$edge_tns"
            if {$name eq $clock} {
              puts -nonewline $graphSlack ",$slack"
            }
    }
  }
  close $csvSlack
  # terminate file with a newline
  puts $graphSlack
  close $graphSlack

  delete_timing_netlist

  project_close
}
