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

extern void ____writeString(char* s);
extern void ____writeHex(unsigned long long n);
extern void __writeDigit(unsigned long long n);

int raise(int base, int exp) {
	int i;
	int ret = 1;
	for (i=0; i<exp; i++) {
		ret *= base;
	}
	return ret;
}

#define RUNS  	 	100L
#define POWS  	 	6L

int arrayBench()
{
  int size, i, j, sum=0;
	int index;
	long long accum;
	long long times[POWS];
	int * indices;
	char * array;
	int runs = 0;
	accum = 0;
	int requestStart, requestEnd;
	for (j=0; j<POWS; j++) times[j] = 0;

  for (size = 1, j=0; j < POWS; size*=10, j++) {
    indices = randomIndexArray(size);
    requestStart = getCount();
    array = malloc(size);//randomArray(size);
    for (i=0; i<size; i++) {
      index = indices[i];
      // This is the manual bounds checking case
      if (index < size) sum += (int)(array[index]);
      else __writeString( "Bounds error!\n");
      // This is the base case with no bounds checking
      //sum += (int)(array[index]);
    }
    freeChar(array);
    requestEnd = getCount();
    if (requestEnd-requestStart > 0) {
      accum += (requestEnd - requestStart);
      runs++;
    }
    freeInt(indices);

    accum = accum/runs;
    //printf( "size: %10d time: %20lld nanoseconds", raise(10,j), accum);
    __writeString( " size: ");
    __writeHex(size);
    __writeString( " sum: ");
    __writeHex(sum);
    __writeString( "\n");
    times[j] += accum;
    accum = 0;
    runs = 0;
    sum = 0;
  }
	__writeString("\nSummary:\n");
	for (j=0; j<POWS; j++) {
		accum = times[j];
		__writeString( "size: ");
    __writeHex(raise(10,j));
    __writeString( "time: 0x");
    __writeHex(accum);
    __writeString( " nanoseconds\n");
	}
	return 0;
}
