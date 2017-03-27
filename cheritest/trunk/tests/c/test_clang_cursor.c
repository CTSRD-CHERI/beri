/*-
 * Copyright (c) 2014 David T. Chisnall
 * Copyright (c) 2015 Michael Roe
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
 * project, funded by EPSRC grant EP/K008528/1.
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
int buffer[42];

extern volatile long long exception_count;

__attribute__((noinline))
void set(__capability int* x)
{
	for (int i=0 ; i<42 ; i++)
	{
		x[i] = i;
	}
}

__attribute__((noinline))
void get(__capability int* x)
{
	for (int i=41 ; i>=0 ; i--,x--)
	{
		assert(*x==i);
	}
}

int test(void)
{
	// Explicitly set the size of the capability
	__capability int *b =
		__builtin_memcap_bounds_set((__capability void*)buffer,
		42*sizeof(int));

	// Check that the base is correctly set to the start of the array
	assert((long long)buffer == __builtin_memcap_base_get(b));

	// Check that the offset is correctly set to the start of the array
	assert(0 == __builtin_memcap_offset_get(b));

	// Check that the length has been set
	assert(42*sizeof(int) == __builtin_memcap_length_get(b));

	// Fill in the array such that every element contains its index
	set(b);

	// Check that pointer arithmetic moves the cursor
	b += 41;
	assert(41*sizeof(int) == __builtin_memcap_offset_get(b));

	// Check that the pointer version of the capability is what we'd expect
	DEBUG_DUMP_REG(18, (int*)b);
	DEBUG_DUMP_REG(19, &buffer);
	assert(((int*)b) == &buffer[41]);

	// Check that we can read all of the array back by reverse iteration
	get(b);

	// Now check some explicit cursor manipulation
	__capability int *v = b;

	// Incrementing the offset shouldn't be visible after setting the
	// offset
	v = __builtin_memcap_offset_increment(v, 42);
	v = __builtin_memcap_offset_set(v, 0);
	assert(__builtin_memcap_offset_get(v) == 0);

	// Nothing in this test should have triggered any exceptions
	assert(exception_count == 0);
	return 0;
}
