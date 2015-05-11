/*-
 * Copyright (c) 2013 Michael Roe
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

#include "assert.h"

typedef __SIZE_TYPE__ size_t;

struct example {
  int x;
};

typedef __capability struct example *example_t;

static __capability void *example_key;

/* If we used the following declaration, the compiler would automatically
 * insert calls to csealdata and cunseal. Instead, we explicitly seal and
 * unseal using compiler built-ins.
 *
 * #pragma opaque example_t example_key
 */

static struct example example_object = {0};

static char *entry[] = {0};

void example_init(void)
{
/*
 * example_key will be used to seal and unseal variables of type example_t.
 * Initialize its otype field to &entry, like this: 
 */
  example_key = __builtin_cheri_set_cap_type((__capability void *) entry, 0);
}

example_t example_constructor(void)
{
  struct example *ptr;
  example_t result;

  ptr = &example_object;

  /*
   * csealdata can only be used to seal capabilities which don't have execute
   * permission, so here we explicitly take away execute permission from the
   * capability for example_object.
   */
  result = (example_t) __builtin_cheri_and_cap_perms((__capability void *) ptr,
    0xd);

  result = __builtin_cheri_seal_cap_data(result, example_key);

  return result;
}

int example_method(example_t o)
{
example_t p;

  p = __builtin_cheri_unseal_cap(o, example_key);
  p->x++;
  return p->x;
}

int test(void)
{
example_t e;
int r;

  example_init();
  e = example_constructor();
  r = example_method(e);
  assert(r == 1);

  return 0;
}
