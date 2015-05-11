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
 * max_cycles.c - decide how many cycles to run a test for before giving up
 *
 * Arguments: name of the test, number of cycles to use for a 'short' test,
 * number of cycles to use for a 'long' test.
 *
 * At present, test_tlb_exception_fill.log is hard-coded as a 'long' test,
 * everything else is a 'short' test.
 */

#include <stdio.h>
#include <strings.h>

int main(int argc, char **argv)
{
int len;
char *cp;

  if (argc < 4)
  {
    fprintf(stderr, "Usage: %s <name of test> <cycle count for short test> <cycle count for long test>\n", argv[0]);
    return -1;
  }

  cp = rindex(argv[1], '/');
  if (cp == (char *) 0)
    cp = argv[1];
  else
    cp++;
  
  if ((strcmp(cp, "test_tlb_exception_fill.log") == 0) ||
      (strcmp(cp, "test_tlb_exception_fill_cached.log") == 0) ||
      (strcmp(cp, "test_tlb_exception_fill_multi.log") == 0) ||
      (strcmp(cp, "test_tlb_exception_fill_cachedmulti.log") == 0) ||
      (strcmp(cp, "test_cp2_tlb_exception_fill.log") == 0) ||
      (strcmp(cp, "test_cp2_tlb_exception_fill_cached.log") == 0) ||
      (strcmp(cp, "test_cp2_tlb_exception_fill_multi.log") == 0) ||
      (strcmp(cp, "test_cp2_tlb_exception_fill_cachedmulti.log") == 0) ||
      (strcmp(cp, "test_mc_llsc.log") == 0) ||
      (strcmp(cp, "test_mc_llsc_cached.log") == 0) ||
      (strcmp(cp, "test_mc_llsc_multi.log") == 0) ||
      (strcmp(cp, "test_mc_llsc_cachedmulti.log") == 0) ||
      (strcmp(cp, "test_mc_llsc_alias.log") == 0) ||
      (strcmp(cp, "test_mc_llsc_alias_cached.log") == 0) ||
      (strcmp(cp, "test_mc_llsc_alias_multi.log") == 0) ||
      (strcmp(cp, "test_mc_llsc_alias_cachedmulti.log") == 0) ||
      (strcmp(cp, "test_mc_tag_coherence.log") == 0) ||
      (strcmp(cp, "test_mc_tag_coherence_cached.log") == 0) ||
      (strcmp(cp, "test_mc_tag_coherence_multi.log") == 0) ||
      (strcmp(cp, "test_mc_tag_coherence_cachedmulti.log") == 0)) 
    printf("%s\n", argv[3]);
  else
    printf("%s\n", argv[2]);

  return 0;
}
