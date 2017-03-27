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

#include <cassert>
#include "stdbool.h"
#include "stdio.h"
#include "stdlib.h"
#include "string.h"
#include <random>
#include <vector>

extern "C" {
#include "dma_test_generation.h"
#include "DMAModel.h"
}

typedef unsigned int uint;

#define MAX(X, Y) ((X) > (Y) ? (X) : (Y));

/*
 * For generating non virtualised tests, need to output:
 * an array of programs
 * source address setting,
 * assertions.
 * an array of source addresses,
 * an array of destination addresses
 */

/*
 * For generating virtualised tests, each program needs to operate in its
 * input and output. The MIPS TLB does this weird thing where it allocates 8K
 * of contiguous virtual address to two potentially non-contiguous memory
 * locations in one way go. Let's allocate each thread an 8K contiguous
 * physical region for input and another for output. The longest generated
 * test I've seen so far takes source up to 0x540 whilst 8K is 0x2000, so we
 * should be ok.
 *
 * What are our restrictions on virtual/physical addressing?
 *
 * User address space is:
 * 0x0000 0000 0000 0000 to
 * 0x3FFF FFFF FFFF FFFF
 *
 * DRAM is:
 * 0x0000 0000 to
 * 0x3FFF FFFF
 *
 * But the "test kernel" will go into DRAM:
 * 0x0010 0000 to
 * 0x0FFF FFFF
 *
 * And all of the access to test goes through the "unmapped region".
 *
 * So allocate pages in physical regions
 * 0x1000 0000 (PN = 0x1 0000) to
 * 0x3FFF FFFF (PN = 0x3 FFFF) (This is 0x2 FFFF pages in total)
 *
 * And virtual pages up to PN
 * 0x0003 FFFF FFFF FFFF
 *
 * We then halve this, because we are actually mapping simulated "8K" pages:
 * we double again before adding the mapping.
 */

#define MIN_PHYS_PAGE   0x08000ULL
#define MAX_PHYS_PAGE   0x1FFFFULL

#define VIRT_PAGE_COUNT 0x1FFFFFFFFFFFFULL

 /*
 * The tests will:
 * - Set up the desired source data (using the physical addresses).
 * - Set up the mappings from source to destination addresses.
 * - Do the aggressive thread switching thing.
 * - Check with physical addresses.
 *
 * We need to output source and dest addrs as normal apart from being in
 * random physical locations.
 *
 * Then output functions to add mappings.
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
generate_programs(uint count, dma_instruction **programs)
{
	for (int i = 0; i < count; ++i) {
		programs[i] = generate_random_dma_program(myrand());
	}
}

void
generate_transfer_lists(uint count,
		struct transfer_record **transfer_lists,
		dma_instruction **programs)
{
	for (int i = 0; i < count; ++i) {
		transfer_lists[i] = list_transfers(programs[i]);
	}
}

void
print_programs(uint program_count, dma_instruction **programs)
{
	for (uint i = 0; i < program_count; ++i) {
		printf("(dma_instruction[]){");
		for (uint j = 0; ; ++j) {
			printf("0x%08x", programs[i][j]);
			if (programs[i][j] == DMA_OP_STOP) {
				break;
			}
			else {
				printf(", ");
			}
		}
		printf("}");
		if (i < (program_count - 1)) {
			printf(", ");
		}
	}
}

inline static dma_address
phys_pn_to_addr(dma_address phys_pn)
{
	return 0x9000000000000000 + (phys_pn << 12);
}

inline static dma_address
virt_pn_to_addr(dma_address virt_pn)
{
	return (virt_pn << 12);
}

template <class Type>
inline static bool
in_vector(Type to_test, const std::vector<Type> &vector)
{
	for (size_t i = 0; i < vector.size(); ++i) {
		if (vector[i] == to_test) {
			return true;
		}
	}
	return false;
}

inline static void
print_pointer_array(uint size, dma_address *array)
{
	for (uint i = 0; i < size; ++i) {
		printf("(uint8_t *)0x%llx", array[i]);
		if (i < (size - 1)) {
			printf(", ");
		}
	}
}

typedef std::uniform_int_distribution<dma_address> uniform_dma_address;

void
print_virtualised_test_information(uint thread_count, uint seed)
{
	mysrand(seed);

	uint i, j;

	dma_instruction **programs = new dma_instruction *[thread_count];

	generate_programs(thread_count, programs);

	struct transfer_record **transfer_lists =
		new struct transfer_record *[thread_count];
	struct transfer_record *current;

	generate_transfer_lists(thread_count, transfer_lists, programs);

	printf("#define DMA_ADDR DMA_VIRT$");
	print_programs(thread_count, programs);
	printf("$");

	/*
	 * We need to create source and destination mappings for each thread,
	 * output the TLB commands to implement the mappings, and create the
	 * initial value settings and assertions.
	 */

	dma_address *source_phys_pns = new dma_address[thread_count];
	dma_address *dest_phys_pns = new dma_address[thread_count];
	dma_address *source_virt_pns = new dma_address[thread_count];
	dma_address *dest_virt_pns = new dma_address[thread_count];

	std::vector<dma_address> used_phys_pns;
	std::vector<dma_address> used_virt_pns;

	dma_address next_addr, usage_bytes, usage_pages;

	std::default_random_engine random_engine(seed);
	uniform_dma_address random_phys_pn(MIN_PHYS_PAGE, MAX_PHYS_PAGE);
	uniform_dma_address random_virt_pn(0, VIRT_PAGE_COUNT);

	for (i = 0; i < thread_count; ++i) {
		// Calculate memory usage of program
		current = transfer_lists[i];
		if (current == NULL) {
			usage_pages = 0;
		}
		else {
			while (current->next != NULL) {
				current = current->next;
			}
			usage_bytes = MAX(current->source, current->destination);
			usage_bytes += 1 << current->size;
			// 0x2000 corresponds to an 8K double-page
			usage_pages = usage_bytes / 0x2000;
		}

		do {
			next_addr = random_phys_pn(random_engine);
		} while (in_vector(next_addr, used_phys_pns));
		for (j = 0; j <= usage_pages; ++j) {
			used_phys_pns.push_back(next_addr + j);
		}
		source_phys_pns[i] = next_addr;

		do {
			next_addr = random_phys_pn(random_engine);
		} while (in_vector(next_addr, used_phys_pns));
		for (j = 0; j <= usage_pages; ++j) {
			used_phys_pns.push_back(next_addr + j);
		}
		dest_phys_pns[i] = next_addr;

		do {
			next_addr = random_virt_pn(random_engine);
			assert(next_addr <= VIRT_PAGE_COUNT);
		} while (in_vector(next_addr, used_virt_pns));
		for (j = 0; j <= usage_pages; ++j) {
			used_virt_pns.push_back(next_addr + j);
		}
		source_virt_pns[i] = next_addr;

		do {
			next_addr = random_virt_pn(random_engine);
			assert(next_addr <= VIRT_PAGE_COUNT);
		} while (in_vector(next_addr, used_virt_pns));
		for (j = 0; j <= usage_pages; ++j) {
			used_virt_pns.push_back(next_addr + j);
		}
		dest_virt_pns[i] = next_addr;
	}

	// We output the mapping before the sources, using the same region of
	// the test. This is naughty, but it works.

	for (i = 0; i < used_phys_pns.size(); ++i) {
		printf("add_tlb_mapping(0x%llx, 0x%llx, 0x%llx);",
			2 * used_virt_pns[i],
			2 * used_phys_pns[i], 2 * used_phys_pns[i] + 1);
	}

	dma_address thread_source, transfer_source;
	uint8_t access_number = 0;
	uint transfer_size;

	for (i = 0; i < thread_count; ++i) {
		thread_source = phys_pn_to_addr(2 * source_phys_pns[i]);
		FOR_EACH(current, transfer_lists[i]) {
			transfer_size = (1 << current->size);
			transfer_source = thread_source + current->source;
			for (j = 0; j < transfer_size; ++j) {
				printf("*((volatile uint8_t *)0x%llx) = %d;",
					transfer_source + j, access_number);
				++access_number;
			}
		}
	}
	printf("$assert(1 ");

	dma_address thread_dest, transfer_dest;
	access_number = 0;
	for (i = 0; i < thread_count; ++i) {
		thread_dest = phys_pn_to_addr(2 * dest_phys_pns[i]);
		FOR_EACH(current, transfer_lists[i]) {
			transfer_size = (1 << current->size);
			transfer_dest = thread_dest + current->destination;
			for (j = 0; j < transfer_size; ++j) {
				printf("&& *((volatile uint8_t *)0x%llx) == %d ",
					transfer_dest + j, access_number);
				++access_number;
			}
		}
	}

	dma_address *source_virt_addrs = new dma_address[thread_count];
	dma_address *dest_virt_addrs = new dma_address[thread_count];

	for (i = 0; i < thread_count; ++i) {
		source_virt_addrs[i] = virt_pn_to_addr(2 * source_virt_pns[i]);
		dest_virt_addrs[i] = virt_pn_to_addr(2 * dest_virt_pns[i]);
	}

	printf(");$");
	print_pointer_array(thread_count, source_virt_addrs);
	printf("$");
	print_pointer_array(thread_count, dest_virt_addrs);

	for (i = 0; i < thread_count; ++i) {
		delete programs[i];
		free_transfer_list(transfer_lists[i]);
	}
	delete programs;
	delete transfer_lists;
	delete source_phys_pns;
	delete source_virt_pns;
	delete source_virt_addrs;
	delete dest_phys_pns;
	delete dest_virt_pns;
	delete dest_virt_addrs;
}

void
print_test_information(uint thread_count, uint seed)
{
	mysrand(seed);

	/* Generate programs, and evaluate results */
	uint i, j;

	dma_instruction **programs = new dma_instruction *[thread_count];

	generate_programs(thread_count, programs);

	struct transfer_record **transfer_lists =
		new struct transfer_record *[thread_count];
	struct transfer_record *current;

	generate_transfer_lists(thread_count, transfer_lists, programs);

	printf("#define DMA_ADDR DMA_VIRT$");
	print_programs(thread_count, programs);
	printf("$");

	dma_address dram_position = DRAM_START;
	dma_address *source_addrs = new dma_address[thread_count];
	dma_address *dest_addrs = new dma_address[thread_count];

	uint8_t access_number = 0;
	uint transfer_size;

	for (i = 0; i < thread_count; ++i) {
		current = transfer_lists[i];
		if (current != NULL) {
			dram_position =
				next_aligned(dram_position, current->size);
			source_addrs[i] = dram_position;
		}

		FOR_EACH(current, transfer_lists[i]) {
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
		current = transfer_lists[i];
		if (current != NULL) {
			dram_position =
				next_aligned(dram_position, current->size);
			dest_addrs[i] = dram_position;
		}
		FOR_EACH(current, transfer_lists[i]) {
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
	print_pointer_array(thread_count, source_addrs);
	printf("$");
	print_pointer_array(thread_count, dest_addrs);
	
	/* Free resources */
	for (i = 0; i < thread_count; ++i) {
		free(programs[i]);
		free_transfer_list(transfer_lists[i]);
	}
	free(programs);
	free(transfer_lists);
	free(source_addrs);
	free(dest_addrs);
}

int
_main(int argc, char* argv[])
{
	std::vector<dma_address> test_data = {3, 0, 2};

	printf("%d\n", in_vector(2ll, test_data));
	printf("%d\n", in_vector(1ll, test_data));
	printf("%d\n", in_vector(3ll, test_data));

	return 0;
}


int
main(int argc, char* argv[])
{
	if (argc != 6 ||
			!(strcmp(argv[1], "virt") == 0 ||
			  strcmp(argv[1], "phys") == 0)) {
		printf(
"Usage: <virt|phys> <min thread count> <max thread count> <min seed> <max seed>\n");
		return 1;
	}
	int thread_lower = atoi(argv[2]);
	int thread_higher = atoi(argv[3]);
	int seed_lower = atoi(argv[4]);
	int seed_higher = atoi(argv[5]);

	for (int i = thread_lower; i <= thread_higher; ++i) {
		for (int j = seed_lower; j <= seed_higher; ++j) {
			if (strcmp(argv[1], "virt") == 0) {
				print_virtualised_test_information(i, j);
			}
			else { //argv[1] == phys
				print_test_information(i, j);
			}
			printf("\n");
		}
	}

	return 0;
}
