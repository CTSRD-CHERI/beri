/*-
 * Copyright (c) 2015 Colin Rothwell
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
#include "stdio.h"
#include "stdlib.h"

#include "dma_test_generation.h"
#include "DMAAsm.h"
#include "DMADisasm.h"
#include "DMAModel.h"

void
print_test_information(unsigned seed)
{
	// Generate test, and output instruction list.
	dma_instruction *program;
	program = generate_random_dma_program(seed);

	for (int i = 0; ; ++i) {
		printf("0x%08x", program[i]);
		if (program[i] == DMA_OP_STOP) {
			break;
		}
		else {
			printf(", ");
#ifdef DISASSEMBLE_DMA
			printf("/* ");
			print_dma_instruction(program[i]);
			printf(" */\n");
#endif
		}
	}
	printf("$");

	uint8_t access_number = 0;
	struct transfer_record *transfer_list, *current;
	transfer_list = list_transfers(program);

	for (current = transfer_list; current != NULL;
			current = current->next) {
		for (int i = 0; i < (1 << current->size); ++i) {
			printf("source[%lld] = %d;",
					current->source + i, access_number);
			++access_number;
		}
		if (current->next == NULL) {
			printf("$%lld$",
				current->source + (1 << current->size));
		}
	}

	access_number = 0;
	printf("assert(1"); // 1 is loop body doesn't have a special case
	for (current = transfer_list; current != NULL;
			current = current->next) {
		for (int i = 0; i < (1 << current->size); ++i) {
			printf(" && dest[%lld] == %d",
					current->destination + i, access_number);
			++access_number;
		}
		if (current->next == NULL) {
			printf(");$%lld",
				current->destination + (1 << current->size));
		}
	}
}

int main(int argc, char* argv[])
{
	if (argc == 2) {
		print_test_information(atoi(argv[1]));
	}
	else if (argc == 3) {
		int lower = atoi(argv[1]);
		int upper = atoi(argv[2]);
		for (int i = lower; i <= upper; ++i) {
			print_test_information(i);
			printf("\n");
		}
	}
	else {
		printf("Invalid number of arguments: %d. Expected 1.\n",
			argc - 1);
	}
	return 0;
}

#ifdef TEST_DMA_TEST_GENERATION
int test_routines()
{
	goto PRINT_PROGRAMS;

	unsigned int lengths[26];
	for (int i = 0; i < 26; ++i)
		lengths[i] = 0;

	for (int i = 0; i < 1000000; ++i) {
		struct dma_program_node *program;
		program = random_dma_program_structure(i);
		lengths[dma_program_length(program)] += 1;
	}

	for (int i = 0; i < 26; ++i) {
		printf("%d\n", lengths[i]);
	}

	return 0;

	dma_instruction *program;
	struct dma_program_node *structure;
PRINT_PROGRAMS:
	for (int i = 0; i < 10; ++i) {
		structure = random_dma_program_structure(i);
		program = random_fill_structure(structure);
		print_dma_program(structure);
		printf("\n");
		for (int j = 0; ; ++j) {
			/*print_dma_instruction(program[j]);*/
			printf("\n");
			if (program[j] == DMA_OP_STOP) {
				break;
			}
		}
		free_dma_structure(structure);
		free(program);
		printf("\n");
	}
	return 0;

	struct transfer_record *res, *last;

	dma_instruction one_transfer[] = {
		DMA_OP_TRANSFER(TS_BITS_32),
		DMA_OP_STOP
	};

	res = list_transfers(one_transfer);
	assert(res->source == 0);
	assert(res->destination == 0);
	assert(res->size == TS_BITS_32);
	assert(res->next == NULL);
	free(res);

	dma_instruction two_transfers[] = {
		DMA_OP_TRANSFER(TS_BITS_8),
		DMA_OP_TRANSFER(TS_BITS_256),
		DMA_OP_STOP
	};

	res = list_transfers(two_transfers);
	assert(res->source == 0);
	assert(res->destination == 0);
	assert(res->size == TS_BITS_8);

	last = res;
	res = res->next;
	free(last);

	assert(res->source == 1);
	assert(res->destination == 1);
	assert(res->size == TS_BITS_256);
	assert(res->next == NULL);

	free(res);

}
#endif
