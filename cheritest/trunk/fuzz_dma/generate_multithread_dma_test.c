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

#include "stdio.h"
#include "stdlib.h"

#include "dma_test_generation.h"
#include "DMAModel.h"

/*
 * Need to output:
 * an array of programs
 * source address setting,
 * assertions.
 * an array of source addresses,
 * an array of destination addresses
 */

#define FOR_EACH(pointer, list)	\
	for(pointer = list; pointer != NULL; pointer = pointer->next)

const dma_address DRAM_START = 0x9000000010000000;

static inline dma_address
next_aligned(dma_address address, enum transfer_size width)
{
	dma_address size_in_bytes = (1 << width);
	dma_address mask = ~((1 << width) - 1);
	return (address + size_in_bytes - 1) & mask;
}

void
print_test_information(unsigned int thread_count, unsigned int seed)
{
	mysrand(seed);

	/* Generate programs, and evaluate results */
	unsigned int i, j;

	size_t prog_arr_size = thread_count * sizeof(dma_instruction *);
	dma_instruction **program = malloc(prog_arr_size);

	for (i = 0; i < thread_count; ++i) {
		program[i] = generate_random_dma_program(myrand());
	}

	size_t tl_arr_size = thread_count * sizeof(struct transfer_record *);
	struct transfer_record **transfer_list = malloc(tl_arr_size);
	struct transfer_record *current;

	for (i = 0; i < thread_count; ++i) {
		transfer_list[i] = list_transfers(program[i]);
	}

	/* Output information */
	for (i = 0; i < thread_count; ++i) {
		printf("(dma_instruction[]){");
		for (j = 0; ; ++j) {
			printf("0x%08x", program[i][j]);
			if (program[i][j] == DMA_OP_STOP) {
				break;
			}
			else {
				printf(", ");
			}
		}
		printf("}");
		if (i < (thread_count - 1)) {
			printf(", ");
		}
	}
	printf("$");

	dma_address dram_position = DRAM_START;
	dma_address *source_addrs = malloc(thread_count * sizeof(dma_address));
	dma_address *dest_addrs = malloc(thread_count * sizeof(dma_address));

	uint8_t access_number = 0;
	unsigned int transfer_size;

	for (i = 0; i < thread_count; ++i) {
		current = transfer_list[i];
		if (current != NULL) {
			dram_position =
				next_aligned(dram_position, current->size);
			source_addrs[i] = dram_position;
		}

		FOR_EACH(current, transfer_list[i]) {
			transfer_size = (1 << current->size);
			dram_position = source_addrs[i] + current->source;
			for (j = 0; j < transfer_size; ++j) {
				printf("*((volatile uint8_t *)0x%llx) = %d;",
					dram_position, access_number);
				++dram_position;
				++access_number;
			}
		}
	}
	printf("$assert(1 ");

	access_number = 0;
	for (i = 0; i < thread_count; ++i) {
		current = transfer_list[i];
		if (current != NULL) {
			dram_position =
				next_aligned(dram_position, current->size);
			dest_addrs[i] = dram_position;
		}
		FOR_EACH(current, transfer_list[i]) {
			transfer_size = (1 << current->size);
			dram_position = dest_addrs[i] + current->destination;
			for (j = 0; j < transfer_size; ++j) {
				printf("&& *((volatile uint8_t *)0x%llx) == %d ",
					dram_position, access_number);
				++dram_position;
				++access_number;
			}
		}
	}


	printf(");$");
	for (i = 0; i < thread_count; ++i) {
		printf("(uint8_t *)0x%llx", source_addrs[i]);
		if (i < (thread_count - 1)) {
			printf(", ");
		}
	}
	printf("$");
	for (i = 0; i < thread_count; ++i) {
		printf("(uint8_t *)0x%llx", dest_addrs[i]);
		if (i < (thread_count - 1)) {
			printf(", ");
		}
	}
	
	/* Free resources */
	for (i = 0; i < thread_count; ++i) {
		free(program[i]);
		free_transfer_list(transfer_list[i]);
	}
	free(program);
	free(transfer_list);
	free(source_addrs);
	free(dest_addrs);
}

int
main(int argc, char* argv[])
{
	if (argc != 5) {
		printf(
"Usage: <min thread count> <max thread count> <min seed> <max seed>\n");
		return 1;
	}
	int thread_lower = atoi(argv[1]);
	int thread_higher = atoi(argv[2]);
	int seed_lower = atoi(argv[3]);
	int seed_higher = atoi(argv[4]);

	for (int i = thread_lower; i <= thread_higher; ++i) {
		for (int j = seed_lower; j <= seed_higher; ++j) {
			print_test_information(i, j);
			printf("\n");
		}
	}

	return 0;
}
