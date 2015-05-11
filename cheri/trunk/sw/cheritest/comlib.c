/*-
 * Copyright (c) 2010 Gregory A. Chadwick
 * Copyright (c) 2010-2014 Jonathan Woodruff
 * Copyright (c) 2011 Steven J. Murdoch
 * Copyright (c) 2011-2013 Robert N. M. Watson
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2012 Ben Thorner
 * Copyright (c) 2013 A. Theodore Markettos
 * Copyright (c) 2013 Philip Withnall
 * Copyright (c) 2013 Alan A. Mujumdar
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
 * license agreements.  See the NOTICE file distributed with this work for
 * additional information regarding copyright ownership.  BERI licenses this
 * file to you under the BERI Hardware-Software License, Version 1.0 (the
 * "License"); you may not use this file except in compliance with the
 * License.  You may obtain a copy of the License at:
 *
 *   http://www.beri-open-systems.org/legal/license-1-0.txt
 *
 * Unless required by applicable law or agreed to in writing, Work distributed
 * under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
 * CONDITIONS OF ANY KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations under the License.
 *
 * @BERI_LICENSE_HEADER_END@
 */

#include "../../../../cherilibs/trunk/include/parameters.h"

#define DRAM_BASE (0x9800000000000000)
#define IO_RD(x) (*(volatile unsigned long long*)(x))
#define IO_RD32(x) (*(volatile int*)(x))
#define IO_WR(x, y) (*(volatile unsigned long long*)(x) = y)
#define IO_WR32(x, y) (*(volatile int*)(x) = y)
#define IO_WR_BYTE(x, y) (*(volatile unsigned char*)(x) = y)

long long context[160];

inline void REGISTER_INTEGRITY_SAVE() {
	asm volatile("daddiu $t0, %0, 0": : "r" (&context));
	asm volatile("sd	$gp,88($t0)\n"
				"sd	$sp,80($t0)\n"
				"sd	$fp,72($t0)\n"
				"sd	$ra,64($t0)\n"
				"sd	$s7,56($t0)\n"
				"sd	$s6,48($t0)\n"
				"sd	$s5,40($t0)\n"
				"sd	$s4,32($t0)\n"
				"sd	$s3,24($t0)\n"
				"sd	$s2,16($t0)\n"
				"sd	$s1,8($t0)\n"
				"sd	$s0,0($t0)\n");
}

inline void REGISTER_INTEGRITY_RESTORE() {
	asm volatile("daddiu $t0, %0, 0": : "r" (&context));
	asm volatile("ld	$gp,88($t0)\n"
				"ld	$sp,80($t0)\n"
				"ld	$fp,72($t0)\n"
				"ld	$ra,64($t0)\n"
				"ld	$s7,56($t0)\n"
				"ld	$s6,48($t0)\n"
				"ld	$s5,40($t0)\n"
				"ld	$s4,32($t0)\n"
				"ld	$s3,24($t0)\n"
				"ld	$s2,16($t0)\n"
				"ld	$s1,8($t0)\n"
				"ld	$s0,0($t0)\n");
				/*: 
				:
				:"$1","$2","$3","$8","$9",
				"$10","$11","$12","$13","$14","$15","$16","$17","$18","$19",
				"$20","$21","$22","$23","$24","$25","$26","$27","$28","$29",
				"$30");*/
}

inline void REGISTER_CONFIDENTIALITY_BARRIER() {
  asm volatile("move $1, $0\n"
	       "move $2, $0\n"
	       "move $3, $0\n"
	       //"move $4, $0\n"
	       //"move $5, $0\n"
	       //"move $6, $0\n"
	       //"move $7, $0\n"
	       "move $8, $0\n"
	       "move $9, $0\n"
	       "move $10, $0\n"
	       "move $11, $0\n"
	       "move $12, $0\n"
	       "move $13, $0\n"
	       "move $14, $0\n"
	       "move $15, $0\n"
	       "move $16, $0\n"
	       "move $17, $0\n"
	       "move $18, $0\n"
	       "move $19, $0\n"
	       "move $20, $0\n"
	       "move $21, $0\n"
	       "move $22, $0\n"
	       "move $23, $0\n"
	       "move $24, $0\n"
	       //"move $25, $0\n"//"jalr $25\n"
	       "move $26, $0\n"
	       "move $27, $0\n"
	       //"move $28, $0\n" 
	       //"move $29, $0\n" // Invalidating the stack pointer breaks the compiler.   We still restore it after the call.
	       //"move $30, $0\n" // Invalidating the frame pointer breaks the compiler.  We still restore it after the call.
	       //"move $31, $0\n" // Will be overwritten by jump and link
	       : 
	       :
	       :"$1","$2","$3","$8","$9",
	       "$10","$11","$12","$13","$14","$15","$16","$17","$18","$19",
	       "$20","$21","$22","$23","$24","$25","$26","$27",/*"$28",*/"$29",
	       "$30");
}



char * heap = (char *)DRAM_BASE;

inline int getCount()
{
	int count;
	asm volatile("dmfc0 %0, $9": "=r" (count));
	return count;
}

/* ====================================================================================
    Subroutines for Sandboxing
   ==================================================================================== */
   
long long makeSandbox(void * addr, long long size, void * capAddr)
{
	long long retVal;
	asm volatile("CIncBase $c1, $c0, %0": : "r" (addr));
	asm volatile("CSetLen $c1, $c1, %0": : "r" (size));
	asm volatile("CIncBase $c2, $c0, %0": : "r" (capAddr));
	asm volatile("CSC $c1, $0, 0($c2)");
	asm volatile("daddiu %0, $v0, 0": "=r" (retVal));
	return retVal;
}

int jumpRaw(void * addr, long long operand)
{
  asm volatile("jalr %0": : "r" (addr));
  asm volatile("daddiu $a0, %0, 0": : "r" (operand));
  return 0;
}

inline int jumpSandbox(void * capAddr, long long funcOffset, long long operand)
{
	int retVal;
	//asm volatile("CLC $c0, %0, 0($c0)": : "r" (capAddr));
	asm volatile("CMOVE $c0, $c1\n"
				 "CJALR %0($c1)": : "r" (funcOffset) : "ra");
	asm volatile("daddiu $a0, %0, 0": : "r" (operand): "a0");
	asm volatile("daddiu %0, $v0, 0": "=r" (retVal));
	return retVal;
}

int returnSandbox()
{
  asm volatile("CJR $31($c24)");
  asm volatile("nop");
  return 0;
}

int invCapRegs()
{
	asm volatile("CClearTag $c1, $c1");
	asm volatile("CClearTag $c2, $c2");
	asm volatile("CClearTag $c3, $c3");
	asm volatile("CClearTag $c4, $c4");
	asm volatile("CClearTag $c5, $c5");
	asm volatile("CClearTag $c6, $c6");
	asm volatile("CClearTag $c7, $c7");
	asm volatile("CClearTag $c8, $c8");
	asm volatile("CClearTag $c9, $c9");
	asm volatile("CClearTag $c10, $c10");
	asm volatile("CClearTag $c11, $c11");
	asm volatile("CClearTag $c12, $c12");
	asm volatile("CClearTag $c13, $c13");
	asm volatile("CClearTag $c14, $c14");
	asm volatile("CClearTag $c15, $c15");
	asm volatile("CClearTag $c16, $c16");
	asm volatile("CClearTag $c17, $c17");
	asm volatile("CClearTag $c18, $c18");
	asm volatile("CClearTag $c19, $c19");
	asm volatile("CClearTag $c20, $c20");
	asm volatile("CClearTag $c21, $c21");
	asm volatile("CClearTag $c22, $c22");
	asm volatile("CClearTag $c23, $c23");
	asm volatile("CClearTag $c24, $c24");
	asm volatile("CClearTag $c25, $c25");
	asm volatile("CClearTag $c26, $c26");
	//asm volatile("CClearTag $c27, $c27");
	//asm volatile("CClearTag $c28, $c28");
	//asm volatile("CClearTag $c29, $c29");
	//asm volatile("CClearTag $c30, $c30");
	//asm volatile("CClearTag $c31, $c31");
	return 0;
}


long long makeSealedCaps(void * addr, long long size, long long entry, void * capAddr, int priv)
{
	long long retVal;
	asm volatile("CIncBase $c1, $c0, %0": : "r" (addr));
	asm volatile("CSetLen $c1, $c1, %0": : "r" (size));
	asm volatile("CSetType $c1, $c1, %0": : "r" (entry));
	asm volatile("CGetPerm $t0, $c1");
	// And with the permissions they passed
	asm volatile("AND $t0, $t0, %0": : "r" (priv));
	// Make sure this one is executable and able to be used to seal.
	asm volatile("ORI $t0, $t0, 0x82");
	asm volatile("CAndPerm $c1, $c1, $t0");
	// Make sure this one is not executable.
	asm volatile("ANDI $t0, $t0, 0x7ffd");
	asm volatile("CAndPerm $c2, $c1, $t0");
	asm volatile("CSealData $c2, $c2, $c1");
	asm volatile("CSealCode $c1, $c1");
	asm volatile("CIncBase $c3, $c0, %0": : "r" (capAddr));
	asm volatile("CSC $c1, $0, 0($c3)");
	asm volatile("CSC $c2, $0, 32($c3)");
	asm volatile("daddiu %0, $v0, 0": "=r" (retVal));
	return retVal;
}

int __attribute__ ((noinline)) jumpSealedSandbox(void * capAddr, long long funcOffset, long long operand)
{
	int retVal;
	
	//asm volatile("CMOVE $c5, $c1");
	//asm volatile("CMOVE $c6, $c2");
	
	//asm volatile("CLC $c0, %0, 0($c0)": : "r" (capAddr));
	asm volatile("CClearTag $c0, $c0");
	asm volatile("CCALL $c5, $c6");
	asm volatile("daddiu $a0, %0, 0": : "r" (operand): "a0");
	asm volatile("ccallReturn:");
	asm volatile("daddiu %0, $v0, 0": "=r" (retVal));
	asm volatile("CGetPCC $0($c0)");
	return retVal;
}

int __attribute__ ((noinline)) jumpUserSandbox(long long operand, void * funcAddr)
{
	int retVal = 0;
	//asm volatile("move $a0, %0": : "r" (operand) : "a0");
	//asm volatile("move $a1, %0": : "r" (funcAddr) : "a1");
	asm volatile("teq $0, $0");
	//asm volatile("move $v0, %0": : "r" (retVal) : "v0");
	return retVal;
}
/*
int __attribute__ ((noinline)) jumpUserSandboxIntegrity(long long operand, void * funcAddr)
{
	int retVal = 0;
	REGISTER_INTEGRITY_SAVE();
	//asm volatile("move $a0, %0": : "r" (operand) : "a0");
	//asm volatile("move $a1, %0": : "r" (funcAddr) : "a1");
	asm volatile("teq $0, $0");
	//asm volatile("move $v0, %0": : "r" (retVal) : "v0");
	REGISTER_INTEGRITY_RESTORE();
	return retVal;
}

int __attribute__ ((noinline)) jumpUserSandboxConfidentiality(long long operand, void * funcAddr)
{
	int retVal = 0;
	REGISTER_INTEGRITY_SAVE();
	REGISTER_CONFIDENTIALITY_BARRIER();
	asm volatile("move $a0, %0": : "r" (operand) : "a0");
	asm volatile("move $a1, %0": : "r" (funcAddr) : "a1");
	asm volatile("teq $0, $0");
	REGISTER_INTEGRITY_RESTORE();
	//asm volatile("move $v0, %0": : "r" (retVal) : "v0");
	return retVal;
}

int safeCallIntegrity(long long operand, int (*f)(int), int capRegs)
{
	REGISTER_INTEGRITY_SAVE();
	int ret = f(operand);
	REGISTER_INTEGRITY_RESTORE();
	return ret;
}

int safeCallConfidentiality(long long operand, int (*f)(int), int capRegs)
{
	REGISTER_INTEGRITY_SAVE();
	REGISTER_CONFIDENTIALITY_BARRIER();
	int ret = f(operand);
	REGISTER_INTEGRITY_RESTORE();
	return ret;
}

int safeCallIntegrity3(long long f, void * operand1, long long operand2, long long operand3)
{
	REGISTER_INTEGRITY_SAVE();  
	//saveContext(ctxAddr, capRegs);
	asm volatile("move $7, $0":::"$7");
	int (*function)(void *, long long, long long)  = (void * )f;
	int ret = function(operand1, operand2, operand3);
	//restoreContext(ctxAddr, capRegs);
	REGISTER_INTEGRITY_RESTORE();
	return ret;
}

int safeCallConfidentiality3(long long f, void * operand1, long long operand2, long long operand3)
{
	REGISTER_INTEGRITY_SAVE();
	REGISTER_CONFIDENTIALITY_BARRIER();  
	//saveContext(ctxAddr, capRegs);
	asm volatile("move $7, $0":::"$7");
	int (*function)(void *, long long, long long)  = (void * )f;
	int ret = function(operand1, operand2, operand3);
	//restoreContext(ctxAddr, capRegs);
	REGISTER_INTEGRITY_RESTORE();
	return ret;
}
*/

/* ====================================================================================
    Subroutines for Array bounds checking benchmark
   ==================================================================================== */

void * malloc(unsigned long size) {
  void * rtnPtr = heap;
  if (heap < (char *)0x9800000010000000) heap += size;
  else heap = (char *)DRAM_BASE;
  rtnPtr = (char *) ((long long)rtnPtr & 0xFFFFFFFFFFFFFFF0);
  return rtnPtr;  
}

void free(void * ptr) {
  
}

int freeChar (char * ptr) {
  return 0;
}

int freeInt (int * ptr) {
  return 0;
}

int * randomIndexArray(int size) {
	int i;
	int *idcs = malloc(size*sizeof(int));
	for (i=0; i<size; i++) {
		idcs[i] = getCount()%size;
	}
	return idcs;
}

char * randomArray(int size) {
	int i;
	char *array = malloc(size);
	for (i=0; i<size; i++) {
		array[i] = i^size;
	}
	return array;
}
