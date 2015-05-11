#!/bin/sh
# Copyright (c) 2011 Wojciech A. Koszek
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
tap=${CHERI_NET_DEV}
br=br0
eth=eth1

if [ "X$tap" = "X" ]; then
	echo "\n\tCHERI_NET_DEV not set!";
	echo
	echo "\tConsult ethercap.c on where it's necessary";
	echo
	echo "\t$0 expects CHERI_NET_DEV to be set, since correct sequence of";
	echo "\tifconfig(8) commands must be run to get networking to work";
	echo "\n\tExiting!";
	exit 64;	# EX_USAGE
fi

ifconfig $br down > /dev/null
ifconfig $tap down > /dev/null
ifconfig $eth down
brctl delbr $br > /dev/null
brctl addbr $br
brctl addif $br $eth
brctl addif $br $tap
brctl setageing $br 0
brctl setfd $br 0
ifconfig $tap hw ether 6:5:4:3:2:1 promisc up
ifconfig $eth hw ether a:b:c:d:e:f promisc up
ifconfig $br hw ether 0:1:2:a:b:c 10.0.0.2
ifconfig $br del fe80::201:2ff:fe0a:b0c/64
ifconfig $tap del fe80::405:4ff:fe03:201/64
