/*-
 * Copyright (c) 2015 David T. Chisnall
 * Copyright (c) 2015 Jonathan Woodruff
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
 * Test that can create a capability to a static struct
 */

#include "assert.h"
//#include "cheri_c_test.h"

_Atomic(char) c = 42;
_Atomic(short) h = 42;
_Atomic(int) w = 42;
_Atomic(long long) d = 42;

int test(void)
{
  assert(*(long long*)&d == 42);
	*(long long*)&d = 42;
	assert(*(long long*)&d == 42);
	assert(d == 42);
	d++;
	assert(d == 43);
	(*(long long*)(&d))++;
	assert(d == 44);
	
	assert(*(int*)&w == 42);
	*(int*)&w = 42;
	assert(*(int*)&w == 42);
	assert(w == 42);
	w++;
	assert(w == 43);
	(*(int*)(&w))++;
	assert(w == 44);
	
	assert(*(short*)&h == 42);
	*(short*)&h = 42;
	assert(*(short*)&h == 42);
	assert(h == 42);
	h++;
	assert(h == 43);
	(*(short*)(&h))++;
	assert(h == 44);
	
	assert(*(char*)&c == 42);
	*(char*)&c = 42;
	assert(*(char*)&c == 42);
	assert(c == 42);
	c++;
	assert(c == 43);
	(*(char*)(&c))++;
	assert(c == 44);
	
  return 0;
}
