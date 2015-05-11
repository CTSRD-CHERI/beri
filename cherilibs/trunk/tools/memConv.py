#-
# Copyright (c) 2010 Gregory A. Chadwick
# Copyright (c) 2010-2013 Jonathan Woodruff
# Copyright (c) 2011 Robert N. M. Watson
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

import os;
import array;
import sys;

def writeMem8(memArray, memSize):
	numDWords = memSize / 8;
	
	if(memSize % 8):
		lastDWordMaxByte = memSize % 8
		numDWords = numDWords + 1
	else:
		lastDWordMaxByte = 8
		
	mems = []
	
	for i in range(0, 8):
		mems.append(open("mem" + str(i) + ".hex", "w"))
		
	for i in range(0, numDWords):
		for j in range(0, 8):
			if(i == numDWords - 1 and j >= lastDWordMaxByte):
				mems[j].write("00\n")
			else:
				mems[j].write("%02X\n" % memArray[i * 8 + j])
				
	for i in range(0, 8):
		mems[i].close()

def writeMem64(memArray, memSize):
	numDWords = memSize / 8;
	
	if(memSize % 8):
		lastDWordMaxByte = memSize % 8
		numDWords = numDWords + 1
	else:
		lastDWordMaxByte = 8
	
	mem64 = open("mem64.hex", "w")
	
	for i in range(0, numDWords):
		value = 0L
		mult = 1L
		for j in range(0, 8):
			if(i == numDWords - 1 and j == lastDWordMaxByte):
				break
			
			value += memArray[i * 8 + j] * mult
			mult *= 256L
			
		mem64.write("%016X\n" % value)
		
	mem64.close()
	
def writeMem32(memArray, memSize):
	numWords = memSize / 4;
	
	if(memSize % 4):
		lastWordMaxByte = memSize % 4
		numWords = numWords + 1
	else:
		lastWordMaxByte = 4
	
	mem64 = open("mem32.hex", "w")
	
	for i in range(0, numWords):
		value = 0L
		mult = 1L
		for j in range(0, 4):
			if(i == numWords - 1 and j == lastWordMaxByte):
				break
			
			value += memArray[i * 4 + j] * mult
			mult *= 256L
			
		mem64.write("%08X\n" % value)
		
	mem64.close()
	
def writeMem256(memArray, memSize):
	print "memSize = ",memSize," bytes"
		
	mems = []
	
	for i in range(0, 8):
		mems.append(open("mem" + str(i) + ".hex", "w"))

	for i in range(0, memSize, 32):
		for j in range(7, -1, -1):
			if(i+j*4 >= memSize-4):
				mems[j].write("00")
				mems[j].write("00")
				mems[j].write("00")
				mems[j].write("00\n")
			else:
				mems[j].write("%02X"   % memArray[i + j*4 + 3])
				mems[j].write("%02X"   % memArray[i + j*4 + 2])
				mems[j].write("%02X"   % memArray[i + j*4 + 1])
				mems[j].write("%02X\n" % memArray[i + j*4])
				
	for i in range(0, 8):
		mems[i].close()
	
def writeMem256C2(memArray, memSize):
	numDWords = memSize / 32;
	
	if(memSize % 32):
		lastDWordMaxByte = memSize % 32
		numDWords = numDWords + 1
	else:
		lastDWordMaxByte = 32
	
	memHex = open("mem.hex", "w")
	
	for i in range(0, numDWords):
		value = 0L
		mult = 1L
		for j in range(0, 32):
			if(i == numDWords - 1 and j == lastDWordMaxByte):
				break
			
			value += memArray[i * 32 + j] * mult
			mult *= 256L
			
		memHex.write("%064X\n" % value)
	
	memHex.close()
	
def writeHex256(memArray, memSize):
	numDWords = memSize / 32;
	
	if(memSize % 32):
		lastDWordMaxByte = memSize % 32
		numDWords = numDWords + 1
	else:
		lastDWordMaxByte = 32
	
	memHex = open("initial.hex", "w")
	
	addr = 0
	
	for i in range(0, numDWords):
		value = 0L
		mult = 1L
		checksum = 0
		for j in range(0, 32):
			if(i == numDWords - 1 and j == lastDWordMaxByte):
				break
			
			value += memArray[i * 32 + j] * mult
			checksum += memArray[i * 32 + j]
			mult *= 256L
			
		checksum += 32 + ((addr >> 8) + (addr & 255))
				
		checksum = checksum & 255
		checksum = -checksum
		checksum = checksum & 255
		
		memHex.write(":20%04X00%064X%02X\n" % (addr, value, checksum))
		addr += 1
	
	memHex.write(':00000001FF')
	memHex.close()
	
def writeHex64(memArray, memSize):
	numDWords = memSize / 8;
	
	if(memSize % 8):
		lastDWordMaxByte = memSize % 8
		numDWords = numDWords + 1
	else:
		lastDWordMaxByte = 8
	
	memHex = open("initial.hex", "w")
	
	addr = 0
	
	for i in range(0, numDWords):
		value = 0L
		mult = 1L
		checksum = 0
		for j in range(0, 8):
			if(i == numDWords - 1 and j == lastDWordMaxByte):
				break
			
			value += memArray[i * 8 + j] * mult
			checksum += memArray[i * 8 + j]
			mult *= 256L
			
		checksum += 8 + ((addr >> 8) + (addr & 255))
				
		checksum = checksum & 255
		checksum = -checksum
		checksum = checksum & 255
		
		memHex.write(":08%04X00%016X%02X\n" % (addr, value, checksum))
		addr += 1
	
	memHex.write(':00000001FF')
	memHex.close()

def writeHex32(memArray, memSize):
	numDWords = memSize / 4;
	
	if(memSize % 4):
		lastDWordMaxByte = memSize % 4
		numDWords = numDWords + 1
	else:
		lastDWordMaxByte = 4
	
	memHex = open("initial.hex", "w")
	
	addr = 0
	
	for i in range(0, numDWords):
		value = 0L
		mult = 1L
		checksum = 0
		for j in range(0, 4):
			if(i == numDWords - 1 and j == lastDWordMaxByte):
				break
			
			value += memArray[i * 4 + j] * mult
			checksum += memArray[i * 4 + j]
			mult *= 256L
			
		checksum += 4 + ((addr >> 8) + (addr & 255))
				
		checksum = checksum & 255
		checksum = -checksum
		checksum = checksum & 255
		
		memHex.write(":04%04X00%08X%02X\n" % (addr, value, checksum))
		addr += 1
	
	memHex.write(':00000001FF')
	memHex.close()

memory = open("mem.bin", 'rb')
memStats = os.stat("mem.bin")
memSize = memStats.st_size

memArray = array.array('B')
memArray.read(memory, memSize)

#
# Pad out to 128-byte line size
#
for i in range (memSize, (memSize + 255) & ~127, 1):
	memArray.append(0);
memSize = (memSize + 255) & ~127;

#for i in range(0, memSize, 4):
#	print i,": ",hex(memArray[i]),hex(memArray[i+1]),hex(memArray[i+2]),hex(memArray[i+3])," ",

if(len(sys.argv) == 2):
	if(sys.argv[1] == "bsim"):
		writeMem256(memArray, memSize)
		writeMem64(memArray, memSize)
		writeMem256C2(memArray, memSize)
	elif(sys.argv[1] == "bsimc2"):
		writeMem256C2(memArray, memSize)
	elif(sys.argv[1] == "verilog"):
		writeHex32(memArray, memSize)
	else:
		print "Please pass either bsim or bsimc2 or verilog"
else:
	writeMem64(memArray, memSize)
