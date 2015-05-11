/*-
 * Copyright (c) 2012 Simon W. Moore
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

// Checks a byte stream to see if a sequence of bytes
// from 0 to 255 is being sent on stdin.

#include <stdio.h>

int main()
{
  int j,k;
  int c = getchar();

  for(j=0,c=0; (c!=EOF); j++) {
    if(j % (1024*1024) == 0)
      printf("Received %0d MB\n", j/(1024*1024));
    if(((unsigned char) c) != ((unsigned char) j)) {
      printf("Diff byte 0x%08x  got 0x%02x\n", j, c);
      c = getchar();
      for(k=0; (k<16) && (c!=EOF); k++) {
	printf("0x%08x  got 0x%02x\n", j, c);
	j++;
	c = getchar();
      }
      c = EOF;
    } else
      c = getchar();
  }
  printf("Checked %d MB = %d = 0x%08x\n", j / (1024*1024), j, j);
  return 0;
}
