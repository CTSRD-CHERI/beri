/*-
 * Copyright (c) 2011-2012 Jonathan Woodruff
 * Copyright (c) 2011 Steven J. Murdoch
 * Copyright (c) 2012 Michael Roe
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



// Capability Register 0
void 	dlnC0		(long decVal) 	{asm("CSetLen $c0, $c0, $a0");}
void 	ibsC0		(long incVal) 	{asm("CIncBase $c0, $c0, $a0");}
void 	stpC0		(long typVal) 	{asm("CSetType $c0, $c0, $a0");}
void 	cpmC0		(long prmVal) 	{asm("CAndPerm $c0, $c0, $a0");}
long 	mvlnC0	() 							{asm("CGetLen $v0, $c0");}
long 	mvbsC0	() 							{asm("CGetBase $v0, $c0");}
long 	mvtpC0	() 							{asm("CGetType $v0, $c0");}
int 	mvpmC0	() 							{asm("CGetPerm $v0, $c0");}



void 	FBIncBase		(long incVal) 								{asm("CIncBase $c4, $c4, $a0");}
void 	FBDecLeng		(long decVal) 								{asm("CSetLen $c4, $c4, $a0");}
long 	FBGetBase		() 														{asm("CGetBase $v0, $c4");}
long 	FBGetLeng		() 														{asm("CGetLen $v0, $c4");}
//void 	FBSBR				(long strVal, long index) 		{asm("CSBR $a0, $c4, $a1");}
void 	FBSBR				(long strVal, long index) 		{
	asm("CSBR $a0, $a1($c4)");
}
void 	FBSWR				(long strVal, long index) 		{
	asm("CSWR $a0, $a1($c4)");
}
void 	FBSDR				(long strVal, long index) 		{
	asm("CSDR $a0, $a1($c4)");
}

long 	CapRegDump				() 		{
	asm("MFC2 $0, $0, 4");
}

int 	mv1kC1	(long source, long dest) 		{
  asm(".word 0x46002000"); // COP1 0x10 (load) $0, 0($a0)
  asm(".word 0x46012001"); // COP1 0x10 (load) $1, 1($a0)
  asm(".word 0x46022002"); // COP1 0x10 (load) $2, 2($a0)
  asm(".word 0x46032003"); 
  asm(".word 0x46042104"); 
  asm(".word 0x46052105"); 
  asm(".word 0x46062106"); 
  asm(".word 0x46072107"); 
  asm(".word 0x46082208");
  asm(".word 0x46092209");
  asm(".word 0x460a220a");
  asm(".word 0x460b220b"); 
  asm(".word 0x460c230c"); 
  asm(".word 0x460d230d"); 
  asm(".word 0x460e230e"); 
  asm(".word 0x460f230f"); 
  asm(".word 0x46102410"); // COP1 0x10 (load) $16, 16($a0)
  asm(".word 0x46112411");
  asm(".word 0x46122412");
  asm(".word 0x46132413"); 
  asm(".word 0x46142514"); 
  asm(".word 0x46152515"); 
  asm(".word 0x46162516"); 
  asm(".word 0x46172517"); 
  asm(".word 0x46182618");
  asm(".word 0x46192619");
  asm(".word 0x461a261a");
  asm(".word 0x461b261b"); 
  asm(".word 0x461c271c"); 
  asm(".word 0x461d271d"); 
  asm(".word 0x461e271e"); 
  asm(".word 0x461f271f"); 
  asm(".word 0x46202800"); // COP1 0x11 (store) $0, 0($a0)
  asm(".word 0x46202841"); // COP1 0x11 (store) $1, 1($a0)
  asm(".word 0x46202882"); // COP1 0x11 (store) $2, 2($a0)
  asm(".word 0x462028C3"); 
  asm(".word 0x46202904"); 
  asm(".word 0x46202945"); 
  asm(".word 0x46202986"); 
  asm(".word 0x462029C7"); 
  asm(".word 0x46202A08");
  asm(".word 0x46202A49");
  asm(".word 0x46202A8a");
  asm(".word 0x46202ACb"); 
  asm(".word 0x46202B0c"); 
  asm(".word 0x46202B4d"); 
  asm(".word 0x46202B8e"); 
  asm(".word 0x46202BCf"); 
  asm(".word 0x46202C10"); // COP1 0x11 (store) $16, 16($a0)
  asm(".word 0x46202C51");
  asm(".word 0x46202C92");
  asm(".word 0x46202CD3"); 
  asm(".word 0x46202D14"); 
  asm(".word 0x46202D55"); 
  asm(".word 0x46202D96"); 
  asm(".word 0x46202DD7"); 
  asm(".word 0x46202E18");
  asm(".word 0x46202E59");
  asm(".word 0x46202E9a");
  asm(".word 0x46202EDb"); 
  asm(".word 0x46202F1c"); 
  asm(".word 0x46202F5d"); 
  asm(".word 0x46202F9e"); 
  asm(".word 0x46202FDf"); 
}

/*char 	lbvcC0	(long index) 		{asm(".word 0x48220100");}
int 	lwvcC0	(long index) 		{asm(".word 0x48420100");}
long 	ldvcC0	(long index) 		{asm(".word 0x48620100");}
void 	sbvcC0	(long index) 		{asm(".word 0x48A20100");}
void	swvcC0	(long index) 		{asm(".word 0x48C20100");}
void 	sdvcC0	(long index) 		{asm(".word 0x48E20100");}
void	lcC0vC0	(long index)		{asm(".word 0x49800100");}
void	scC0vC0	(long index)		{asm(".word 0x49A00100");}
void 	jcrC0		(long index) 		{asm(".word 0x49000100");asm("nop");}
void 	jalcrC0	(long index) 		{asm(".word 0x4A400100");asm("nop");}

// Capability Register 1
void 	dlnC1		(long decVal) 	{asm("mtc2 $a0, $1, 0");}
void 	ibsC1		(long decVal) 	{asm("mtc2 $a0, $1, 1");}
void 	stpC1		(long decVal) 	{asm("mtc2 $a0, $1, 2");}
void 	cpmC1		(long decVal) 	{asm("mtc2 $a0, $1, 3");}
void 	cusC1		(long decVal) 	{asm("mtc2 $a0, $1, 4");}
long 	mvlnC1	() 							{asm("mfc2 $v0, $1, 0");}
long 	mvbsC1	() 							{asm("mfc2 $v0, $1, 1");}
long 	mvtpC1	() 							{asm("mfc2 $v0, $1, 2");}
int 	mvpmC1	() 							{asm("mfc2 $v0, $1, 3");}
char 	mvusC1	() 							{asm("mfc2 $v0, $1, 4");}
char 	lbvcC1	(long index) 		{asm(".word 0x48220900");}
int 	lwvcC1	(long index) 		{asm(".word 0x48420900");}
long 	ldvcC1	(long index) 		{asm(".word 0x48620900");}
void 	sbvcC1	(long index) 		{asm(".word 0x48A20900");}
void	swvcC1	(long index) 		{asm(".word 0x48C20900");}
void 	sdvcC1	(long index) 		{asm(".word 0x48E20900");}
void	lcC1vC1	(long index)		{asm(".word 0x49810900");}
void	scC1vC1	(long index)		{asm(".word 0x49A10900");}
void 	jcrC1		(long index) 		{asm(".word 0x49000900");asm("nop");}
void 	jalcrC1	(long index) 		{asm(".word 0x4A400900");asm("nop");}*/

