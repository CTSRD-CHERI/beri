/*-
 * Copyright (c) 2014 Michael Roe
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

/*
 * Fuzz test for floating point instructions.
 *
 * This program will create a raw test containing randomly-generated
 * floating point instructions. Many of the FP instructions will be
 * invalid instructions. The purpose of this fuzzer is to catch CPU bugs
 * in which a malformed FP instruction locks up the pipeline.
 */

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
int i;
unsigned int r;

  srandom(time(0));

  printf(".set mips64\n");
  printf(".set noreorder\n");
  printf(".set nobopt\n");
  printf(".set noat\n");
  printf("\n");

  printf("\t\t.text\n");
  printf("\t\t.global start\n");
  printf("\t\t.ent start\n");
  printf("start:\n"); 

  printf("\t\tmfc0 $t0, $12\n");
  printf("\t\tli $t1, 1 << 29\n");
  printf("\t\tor $t0, $t0, $t1\n");
  printf("\t\tmtc0 $t0, $12\n");
  printf("\t\tnop\n");
  printf("\t\tnop\n");
  printf("\t\tnop\n");

  for (i=0; i<1024; i++)
  {
    r = (unsigned int) random();
    r = r & 0x00bfffff;
    r = r | 0x46000000;
    printf("\t\t.word 0x%08x\n", r);
  }

  printf("\t\tmtc0 $at, $26\n");
  printf("\t\tnop\n");
  printf("\t\tnop\n");
  printf("\t\tmtc0 $at, $23\n");
  printf("end:\n");
  printf("\t\tb end\n");
  printf("\t\tnop\n");
  printf(".end start\n");

  return 0;
}
