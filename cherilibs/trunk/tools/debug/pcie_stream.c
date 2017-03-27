/*-
 * Copyright (c) 2014 Alex Horsman
 * Copyright (c) 2015 Theo Markettos
 *
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


#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <time.h>
#include "macosx.h"
#include "cheri_debug.h"

#ifdef ENABLE_PCIEXPRESS
#include <pciaccess.h>
#endif

const int BUFFER_SIZE = 64*1024;

#ifdef ENABLE_PCIEXPRESS
const struct pci_id_match DE4_BERI_MATCH = {
	.vendor_id         = 0x00001172,
	.device_id         = 0x00000de4,
	.subvendor_id      = 0x00001172,
	.subdevice_id      = 0x00000004,
	.device_class      = 0x00000000,
	.device_class_mask = 0x00000000
};
#endif

int max(int x, int y) { return (x > y) ? x : y; }
int min(int x, int y) { return (x < y) ? x : y; }

/* TODO: Should include size (in hardware as well). */
typedef struct {
	volatile	uint64_t*	head;
	volatile	uint64_t*	tail;
	volatile	uint8_t*	data;
} pci_ring;

int
ring_fill_count(pci_ring ring)
{
	return (*ring.tail - *ring.head) % BUFFER_SIZE;
}

int
ring_free_space(pci_ring ring)
{
	return (BUFFER_SIZE - ring_fill_count(ring)) - 1;
}

size_t
wrap_read(void *ptr, size_t bytes, int stream)
{
	int result = read(stream, ptr, bytes);
	if (result < 0) {
		if (result == EAGAIN) {
			return 0;
		} else {
			err(1,"read");
		}
	}
	return result;
}

size_t
wrap_write(const void *ptr, size_t bytes, int stream)
{
	int result = write(stream, ptr, bytes);
	if (result < 0) {
		if (result == EAGAIN) {
			return 0;
		} else {
			err(1,"write");
		}
	}
	return result;
}

size_t
read_to_ring(pci_ring ring, int stream)
{
	int free_space = ring_free_space(ring);
	int buffer_span = BUFFER_SIZE - *ring.tail;

	/* Suppress volatile warnings. Safe because we only write(?) */
	uint8_t* data = (uint8_t*)ring.data;

	/* Fill to head or end of buffer. */
	size_t read_request = min(free_space,buffer_span);
	size_t read_total = wrap_read(&data[*ring.tail], read_request, stream);
	if (read_total == buffer_span) {
		/* Fill from buffer start if we hit the end. */
		read_request = free_space - buffer_span;
		read_total += wrap_read(&data[0], read_request, stream);
	}
	*ring.tail = (*ring.tail + read_total) % BUFFER_SIZE;
	return read_total;
}

size_t
write_from_ring(pci_ring ring, int stream)
{
	int fill_count = ring_fill_count(ring);
	int buffer_span = BUFFER_SIZE - *ring.head;

	/* Suppress volatile warnings. Safe because we only read static data(?) */
	uint8_t* data = (uint8_t*)ring.data;

	/* Read to tail or end of buffer. */
	size_t write_request = min(fill_count,buffer_span);
	size_t write_total = wrap_write(&data[*ring.head], write_request, stream);
	if (write_total == buffer_span) {
		/* Read from start if we hit the end. */
		write_request = fill_count - buffer_span;
		write_total += wrap_write(&data[0], write_request, stream);
	}
	*ring.head = (*ring.head + write_total) % BUFFER_SIZE;
	return write_total;
}

int
pcie_stream_init(pci_ring *in, pci_ring *out)
{
#ifdef ENABLE_PCIEXPRESS
	int ret = pci_system_init();
	if (ret != 0) {
		err(1,"pci_system_init");
	}

	struct pci_device_iterator *iter;
	iter = pci_id_match_iterator_create(&DE4_BERI_MATCH);
	if (iter == NULL) {
		err(1,"pci_id_match_iterator_create");
	}

	struct pci_device *dev;
	dev = pci_device_next(iter);
	if (dev == NULL) {
		errx(1,"Device not found!\n");
	}
	pci_device_probe(dev);

	struct pci_mem_region *ctrl_region;
	ctrl_region = &dev->regions[2];

	volatile uint64_t* ctrl_map;
	ret = pci_device_map_range(dev,
		ctrl_region->base_addr,
		ctrl_region->size,
		PCI_DEV_MAP_FLAG_WRITABLE,
		(void**)&ctrl_map
	);
	if (ret != 0) {
		errno = ret;
		err(1,"pci_device_map_range");
	}

	in->head = &ctrl_map[0];
	in->tail = &ctrl_map[1];
	out->head = &ctrl_map[2];
	out->tail = &ctrl_map[3];

	struct pci_mem_region *data_region;
	data_region = &dev->regions[0];

	volatile uint8_t* data_map;
	ret = pci_device_map_range(dev,
		data_region->base_addr,
		data_region->size,
		PCI_DEV_MAP_FLAG_WRITABLE,
		(void**)&data_map
	);
	if (ret != 0) {
		errno = ret;
		err(1,"pci_device_map_range");
	}

	in->data = &data_map[0];
	out->data = &data_map[data_region->size/2];

	return 0;
#else
	return BERI_DEBUG_ERROR_PCIEXPRESS_DISABLED;
#endif
}


int
pcie_stream_start(int stream)
{
	pci_ring in;
	pci_ring out;
	pcie_stream_init(&in,&out);

	struct timeval TIMEOUT = { .tv_sec = 0, .tv_usec = 1000 };

	fd_set readfds;
	fd_set writefds;

	while (1) {
		struct timeval timeout = TIMEOUT;

		FD_ZERO(&readfds);
		if (ring_free_space(in) != 0) {
			FD_SET(stream,&readfds);
		}
		FD_ZERO(&writefds);
		if (ring_fill_count(out) != 0) {
			FD_SET(stream,&writefds);
		}
		int sel = select(FD_SETSIZE, &readfds, &writefds, NULL, &timeout);
		if (sel == -1) {
			err(1,"select");
		}
		if (FD_ISSET(stream,&readfds)) {
			read_to_ring(in,stream);
		}
		if (FD_ISSET(stream,&writefds)) {
			write_from_ring(out,stream);
		}
	}

	return 0;
}
