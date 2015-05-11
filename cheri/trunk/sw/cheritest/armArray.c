/*-
 * Copyright (c) 2013-2014 Jonathan Woodruff
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

//#include "comlib.c"
#include "armArray.h"
//#include "box.c"

extern int box_get_jal(int i);
extern int box_get_cjalr(int i);
extern int box_get_ccall(int i);
extern int box_get_user(int i);
extern char __box_start;
extern char __box_size;
extern void __writeString(char* s);
extern void __writeHex(unsigned long long n);
extern void __writeDigit(unsigned long long n);

// Just create some space outputs based a a value so that the value can't be
// optimised away.
int spaceOut(int val)
{
  for (; val>0; val-=10000) {
    if ((val % 100000)==0) __writeString(" ");
  }
}

int write2DecimalDigit(int val)
{
  __writeDigit(val/100);
  __writeString( ".");
  __writeDigit(val%100);
}

//long long f = (long long)(&jumpSandbox);

int armArray()
{
	int i, sum;
	long long time;
	long long mean = 0;
	// Enough space for 1 aligned capability, and then align it.
	long long spotA[16];
	void * boxCap = &spotA;
	boxCap = (void *)((long long)boxCap & ~0x1F) + 32;
	long long spotB[16];
	void * boxCapSealed = &spotB;
	boxCapSealed = (void *)((long long)boxCapSealed & ~0x1F) + 32;
	long long spotC[16];
	void * retCapSealed = &spotC;
	retCapSealed = (void *)((long long)retCapSealed & ~0x1F) + 32;
  
	// ------- boxCap is the aligned pointer --------
	int requestStart, requestEnd;
	
	sum = 0;
  	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		REGISTER_INTEGRITY_RESTORE();
		//safeCallIntegrity(1, getCount, 0);
		//sum += getCount();
	  
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = (100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t Context Save & Restore\n");
	
	/* ********** Access array directly, no protection ************************ */
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		sum += box_get_jal(i);
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = 	(100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t Direct\n");
	
	/* ********** Access array directly with Integrity ************************ */
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		sum += box_get_jal(i);
		REGISTER_INTEGRITY_RESTORE();
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = (100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t Direct with Integrity\n");
	
	/* ********** Access array directly with Confidentiality ************************ */
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		REGISTER_CONFIDENTIALITY_BARRIER();
		sum += box_get_jal(i);
		REGISTER_INTEGRITY_RESTORE();
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = (100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t Direct with Confidentiality\n");
	
	/* ********** Access array in userspace sandbox ********************** */
	void *userBoxAddr = (void *)(((long long)&box_get_user) & 0x00000000FFFFFFFF); 
	// Get "physical" address, which is a translated address.
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		sum += jumpUserSandbox(i, userBoxAddr);
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = (100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t Userspace\n");
	
	/* ********** Access array in userspace sandbox with integrity. ********************** */ 
	// Get "physical" address, which is a translated address.
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		sum += jumpUserSandbox(i, userBoxAddr);
		REGISTER_INTEGRITY_RESTORE();
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = (100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t Userspace with Integrity\n");
	
	/* ********** Access array in userspace sandbox with Confidentiality ********************** */
	// Get "physical" address, which is a translated address.
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		REGISTER_CONFIDENTIALITY_BARRIER();
		sum += jumpUserSandbox(i, userBoxAddr);
		REGISTER_INTEGRITY_RESTORE();
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = (100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t Userspace with Confidentiality\n");
	
	/* ********** Access array in C0 sandbox ********************** */
	makeSandbox(&__box_start, (long long)&__box_size, boxCap);
	sum = 0;
	long long box_get_offset = ((long long)&box_get_cjalr)-((long long) &__box_start);
	asm volatile("CLC $c1, %0, 0($c0)": : "r" (boxCap));
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		sum += jumpSandbox(boxCap, box_get_offset, i);
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = (100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t C0 Constrained\n");
	
	/* ********** Access array in C0 sandbox integrity ********************** */
	sum = 0;
	box_get_offset = ((long long)&box_get_cjalr)-((long long) &__box_start);
	asm volatile("CLC $c1, %0, 0($c0)": : "r" (boxCap));
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		sum += jumpSandbox(boxCap, box_get_offset, i);
		REGISTER_INTEGRITY_RESTORE();
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = 	(100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t C0 Constrained with Integrity\n");
	
	/* ********** Access array in C0 sandbox confidentiality ********************** */
	sum = 0;
	box_get_offset = ((long long)&box_get_cjalr)-((long long) &__box_start);
	asm volatile("CLC $c1, %0, 0($c0)": : "r" (boxCap));
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		REGISTER_CONFIDENTIALITY_BARRIER();
		sum += jumpSandbox(boxCap, box_get_offset, i);
		REGISTER_INTEGRITY_RESTORE();
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = 	(100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t C0 Constrained with Confidentialtiy\n");
	
	/* ********** Access array in secure sandbox ********************** */
	invCapRegs();
	long long box_get_ccall_offset = ((long long)&box_get_ccall)-((long long) &__box_start);
	makeSealedCaps(&__box_start, (long long)&__box_size, box_get_ccall_offset, boxCapSealed, 0xffff);
	asm volatile("CLC $c5, %0, 0($c0)": : "r" (boxCapSealed));
	asm volatile("CLC $c6, %0, 32($c0)": : "r" (boxCapSealed));
	void * returnAddr;
	asm volatile("dla %0, ccallReturn": "=r" (returnAddr));
	makeSealedCaps((void *)0, -1, (long long)returnAddr, retCapSealed, 0xffff);
	asm volatile("CLC $c1, %0, 0($c0)": : "r" (retCapSealed));
	asm volatile("CLC $c2, %0, 32($c0)": : "r" (retCapSealed));
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		sum += jumpSealedSandbox(boxCapSealed, box_get_offset, i);
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = 	(100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t CCall\n");
	
	/* ********** Access array in secure sandbox integrity ********************** */
	invCapRegs();
	box_get_ccall_offset = ((long long)&box_get_ccall)-((long long) &__box_start);
	makeSealedCaps(&__box_start, (long long)&__box_size, box_get_ccall_offset, boxCapSealed, 0x7fff);
	asm volatile("CLC $c5, %0, 0($c0)": : "r" (boxCapSealed));
	asm volatile("CLC $c6, %0, 32($c0)": : "r" (boxCapSealed));
	asm volatile("dla %0, ccallReturn": "=r" (returnAddr));
	makeSealedCaps((void *)0, -1, (long long)returnAddr, retCapSealed, 0xffff);
	asm volatile("CLC $c1, %0, 0($c0)": : "r" (retCapSealed));
	asm volatile("CLC $c2, %0, 32($c0)": : "r" (retCapSealed));
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		sum += jumpSealedSandbox(boxCapSealed, box_get_offset, i);
		REGISTER_INTEGRITY_RESTORE();
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = 	(100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t CCall with Integrity\n");
	
	/* ********** Access array in secure sandbox confidentiality ********************** */
	invCapRegs();
	box_get_ccall_offset = ((long long)&box_get_ccall)-((long long) &__box_start);
	makeSealedCaps(&__box_start, (long long)&__box_size, box_get_ccall_offset, boxCapSealed, 0x7fff);
	asm volatile("CLC $c5, %0, 0($c0)": : "r" (boxCapSealed));
	asm volatile("CLC $c6, %0, 32($c0)": : "r" (boxCapSealed));
	asm volatile("dla %0, ccallReturn": "=r" (returnAddr));
	makeSealedCaps((void *)0, -1, (long long)returnAddr, retCapSealed, 0xffff);
	asm volatile("CLC $c1, %0, 0($c0)": : "r" (retCapSealed));
	asm volatile("CLC $c2, %0, 32($c0)": : "r" (retCapSealed));
	sum = 0;
	requestStart = getCount();
	for (i = 0; i < DCRUNS; i++) {
		REGISTER_INTEGRITY_SAVE();
		REGISTER_CONFIDENTIALITY_BARRIER();
		sum += jumpSealedSandbox(boxCapSealed, box_get_offset, i);
		REGISTER_INTEGRITY_RESTORE();
	}
	requestEnd = getCount();
	spaceOut(sum);
	time = (requestEnd - requestStart);
	mean = 	(100*time)/DCRUNS;
	write2DecimalDigit(mean);
	__writeString( "\t CCall with Confidentiality\n");
	
	return 0;
}
