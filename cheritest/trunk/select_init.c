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

#include <stdio.h>
#include <string.h>

#define BUILD_UNCACHED 0
#define BUILD_CACHED 1
#define BUILD_UNCACHED_MULTI 2
#define BUILD_CACHED_MULTI 3

/*
 * select_init: program to select which linker script and initialization
 * object code to use when linking a test. A C program is used for this
 * because using Make wildcards is too complicated.
 */

int main(int argc, char **argv)
{
char *cp;
char *cp1;
int build;

  if (argc < 2)
  {
    fprintf(stderr, "Usage: %s <filename>\n", argv[0]);
    return -1;
  }

  cp = argv[1];
  /* remove any path before the file name */
  cp1 = rindex(cp, '/');
  if (cp1)
    cp = cp1 + 1;

  if (strstr(cp, "_cachedmulti.elf"))
    build = BUILD_CACHED_MULTI;
  else if (strstr(cp, "_multi.elf"))
    build = BUILD_UNCACHED_MULTI;
  else if (strstr(cp, "_cached.elf"))
    build = BUILD_CACHED;
  else 
    build = BUILD_UNCACHED;

  if (strncmp(cp, "test_raw_mc_", 12) == 0)
  {
    /*
     * raw multicore tests are assumed to know about multiple cores and
     * handle them explicitly, so they don't get linked against the
     * multicore initialization in init_multi.s
     */
    switch (build)
    {
      case BUILD_UNCACHED:
        printf("-Traw.ld\n");
        break;
      case BUILD_CACHED:
        printf("-Traw_cached.ld obj/init_cached.o\n");
        break;
      case BUILD_UNCACHED_MULTI:
        /* raw_mc tests are aware of cores, so just link with raw.ld */
        printf("-Traw.ld\n");
        break;
      case BUILD_CACHED_MULTI:
        printf("-Traw_cached.ld obj/init_cached.o\n");
    }
  }
  else if (strncmp(cp, "test_raw_", 9) == 0)
  {
    switch (build)
    {
      case BUILD_UNCACHED:
        printf("-Traw.ld\n");
        break;
      case BUILD_CACHED:
        printf("-Traw_cached.ld obj/init_cached.o\n");
        break;
      case BUILD_UNCACHED_MULTI:
        /* init_multi.o will work for cached and uncached */
        printf("-Traw_multi.ld obj/init_multi.o\n");
        break;
      case BUILD_CACHED_MULTI:
        /* init_multi.o will work for cached and uncached */
        printf("-Traw_cachedmulti.ld obj/init_multi.o\n");
        break;
    }
  }
  else
  {
    switch (build)
    {
      case BUILD_UNCACHED:
        printf("-Ttest.ld obj/lib.o\n");
        break;
      case BUILD_CACHED:
        printf("-Ttest_cached.ld obj/init_cached.o obj/lib.o\n");
        break;
      case BUILD_UNCACHED_MULTI:
        /* Non-raw tests don't need init_multi.o, because init.o takes
         * care of multicore initialization.
         */
        printf("-Ttest_cached.ld obj/lib.o\n");
        break;
      case BUILD_CACHED_MULTI:
        /* Non-raw tests don't need init_multi.o */
        printf("-Ttest_cached.ld obj/init_cached.o obj/lib.o\n");
        break;
    }
  }

  return 0;
}
