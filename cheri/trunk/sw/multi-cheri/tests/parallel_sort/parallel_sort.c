/*-
 * Copyright (c) 2014 Alan Mujumdar
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
 *
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C (BERI) under one or more contributor
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

#include "parallel_sort.h"
#include "core.h"
#include "uart.h"

#define ARRAY_SIZE 20
volatile unsigned int shared_array[ARRAY_SIZE];

unsigned int lfsr(void)
{
	static unsigned int a = 12345, b = 23456, c = 34567, d = 45678, e = 56789;
	unsigned int x = 0;
	x = ((a << 5) ^ a) >> 7;
	a = ((a & 97587842537U) << 8) ^ x;
	x = ((b << 9) ^ b) >> 11;
	b = ((b & 17436597364U) << 12) ^ x;
 	x = ((c << 13) ^ c) >> 15;
	c = ((c & 78156613458U) << 16) ^ x;
	x = ((d << 17) ^ d) >> 19;
	d = ((d & 23455357684U) << 20) ^ x;
	x = ((e << 21) ^ e) >> 23;
	e = ((e & 45634657864U) << 24) ^ x;
	return (a ^ b ^ c ^ d ^ e);
}

int sort(int head, int tail)
{
	int i = 0;
	int swap = 0;

	do 
	{	
		swap = 0;

		for (i = head; i < tail; i++)
		{
			if (shared_array[i] > shared_array[i + 1])
			{
				int tmp = shared_array[i];	
				shared_array[i] = shared_array[i + 1];
				shared_array[i + 1] = tmp;
				swap++;
			}
		}
	}
	while (swap > 0);
}

int block_sort(int loop_count)
{
	int core_no = core_id();
	int segment = ARRAY_SIZE/loop_count;
	int head = core_no*segment;
	int tail = (core_no + 1)*segment - 1;
	if ((core_no + 1) >= loop_count)
	{
		tail = ARRAY_SIZE - 1;
	}
	sort(head, tail);
}

int parallel_sort_main(test_function_t * mtest)
{
	int i = 0;

	// Initialisation 
	for (i = 0; i < ARRAY_SIZE; i++)
	{
		shared_array[i] = lfsr();
		uart_puts("\n Unsorted[");
		uart_putd(i);
		uart_puts("]   : ");
		uart_putd(shared_array[i]);
	}
	uart_puts("\n");

	// Dive and Conquer
	int core_count = core_total();
	int tmp_core_count = core_count;
	if (ARRAY_SIZE/2 < core_count)
	{
		tmp_core_count = ARRAY_SIZE/2;
	}

	while (tmp_core_count >= 1)
	{
		// Begin sorting
		block_sort(tmp_core_count);

		// Display sorted blocks
		for (i = 0; i < ARRAY_SIZE; i++)
		{
			uart_puts("\n Part-sorted[");
			uart_putd(i);
			uart_puts("]: ");
			uart_putd(shared_array[i]);
		}
		uart_puts("\n");
	
		tmp_core_count = tmp_core_count/2;
	}

	// Display final sorted array
	for (i = 0; i < ARRAY_SIZE; i++)
	{
		uart_puts("\n Sorted[");
		uart_putd(i);
		uart_puts("]     : ");
		uart_putd(shared_array[i]);
	}

	uart_puts("\n\n");
	return 0;
}

