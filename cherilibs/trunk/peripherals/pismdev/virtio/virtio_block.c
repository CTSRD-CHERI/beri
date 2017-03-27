/*-
 * Copyright (c) 2015 Ruslan Bukin <br@bsdpad.com>
 * All rights reserved.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the CTSRD Project, with support from the UK Higher
 * Education Innovation Fund (HEIF).
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

#define _BSD_SOURCE
#define _XOPEN_SOURCE 500

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/queue.h>
#include <sys/stat.h>
#include <sys/uio.h>

#include <bsd/string.h>

#include <assert.h>
#if defined(__linux__)
#include <endian.h>
#elif (__FreeBSD__)
#include <sys/endian.h>
#endif
#include <err.h>
#include <fcntl.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <stdbool.h>
#include <unistd.h>

#include "pismdev/pism.h"
#include "pismdev/dram/dram.h"

#include "virtio_mmio.h"
#include "virtio_blk.h"
#include "virtio_ids.h"
#include "virtio_config.h"
#include "virtio_ring.h"
#include "virtio.h"

/* PISM simulation of the Virtio Block Device */

static pism_mod_init_t			vtblk_mod_init;
static pism_dev_interrupt_get_t		vtblk_dev_interrupt_get;
static pism_dev_request_ready_t		vtblk_dev_request_ready;
static pism_dev_request_put_t		vtblk_dev_request_put;
static pism_dev_response_ready_t	vtblk_dev_response_ready;
static pism_dev_response_get_t		vtblk_dev_response_get;
static pism_dev_addr_valid_t		vtblk_dev_addr_valid;

/* We use indirect descriptors */
#define	NUM_DESCS	1
#define	NUM_QUEUES	1

#define	VTBLK_BLK_ID_BYTES	20
#define	VTBLK_MAXSEGS		256

#define	MMIO_WINDOW_SIZE	512

/* FreeBSD compatibility */
#define	ENOSYS		22
#define	DEV_BSIZE	512
#define	MIN(a,b)	(((a)<(b))?(a):(b))
#define	roundup2(x, y)	(((x)+((y)-1))&(~((y)-1))) /* if y is powers of two */

/*
 * Data structure describing virtio block device instance fields, hung off of
 * pism_device_t->pd_private.
 */
struct vtblk_private {
	int		sdp_imagefile;		/* Image file. */
	uint64_t	sdp_length;		/* Image file length. */
	pism_data_t	sdp_reqfifo;
	bool		sdp_reqfifo_empty;
	unsigned int	sdp_delay;
	uint64_t	sdp_replycycle;  /* Earliest cycle reply permitted. */

	pism_device_t	*dev;
	uint8_t		mmio_data[MMIO_WINDOW_SIZE];
	uint64_t	mem_offset;
	char		ident[VTBLK_BLK_ID_BYTES];
	uint8_t		intr;

	struct virtio_blk_config	*cfg;
	struct vqueue_info		vs_queues[NUM_QUEUES];
};

/*
 * Virtio block option names.
 */
#define	VTBLK_OPTION_PATH	"path"	/* File system path to memory map. */

static char		*g_vtblk_debug = NULL;

#define	DDBG(...)	do	{		\
	if (g_vtblk_debug == NULL) {		\
		break;				\
	}					\
	printf("%s(%d): ", __func__, __LINE__);	\
	printf(__VA_ARGS__);			\
	printf("\n");				\
} while (0)

static void
virtio_init(struct vtblk_private *sdpp)
{
	struct virtio_blk_config *cfg;
	uint8_t *data;
	uint32_t *s;
	int reg;
	int i;

	data = (uint8_t *)&sdpp->mmio_data;

	/* Specify that we provide block device */
	reg = htobe32(VIRTIO_ID_BLOCK);
	*(volatile uint32_t *)(data + VIRTIO_MMIO_DEVICE_ID) = reg;

	/* Queue size */
	reg = htobe32(NUM_DESCS);
	*(volatile uint32_t *)(data + VIRTIO_MMIO_QUEUE_NUM_MAX) = reg;

	/* Our features */
	reg = htobe32(VIRTIO_RING_F_INDIRECT_DESC
	    | VIRTIO_BLK_F_BLK_SIZE
	    | VIRTIO_BLK_F_SEG_MAX);
	*(volatile uint32_t *)(data + VIRTIO_MMIO_HOST_FEATURES) = reg;

	cfg = sdpp->cfg;
	cfg->capacity = htobe64(sdpp->sdp_length / DEV_BSIZE);
	cfg->size_max = 0; /* not negotiated */
	cfg->seg_max = htobe32(VTBLK_MAXSEGS);
	cfg->blk_size = htobe32(DEV_BSIZE);

	s = (uint32_t *)cfg;
	for (i = 0; i < sizeof(struct virtio_blk_config); i += 4) {
		*(volatile uint32_t *)(data + VIRTIO_MMIO_CONFIG + i) = *s;
		s += 1;
	}

	sprintf(sdpp->ident, "PISM Virtio Block Device");
}

static int
vq_init(struct vtblk_private *sdpp)
{
	struct vqueue_info *vq;
	uint8_t *base;
	uint8_t *data;
	uint32_t size;
	int reg;
	int pfn;

	DDBG("vq init addr 0x%016lx", (uint64_t)&vq_init);

	data = (uint8_t *)&sdpp->mmio_data;

	vq = &sdpp->vs_queues[0];
	vq->vq_qsize = NUM_DESCS;

	reg = *(volatile uint32_t *)(data + VIRTIO_MMIO_QUEUE_PFN);
	pfn = be32toh(reg);
	vq->vq_pfn = pfn;

	size = vring_size(vq->vq_qsize, VRING_ALIGN);
	base = paddr_map(sdpp->mem_offset,
		(pfn << PAGE_SHIFT), size);

	DDBG("mem_offset is 0x%016lx base is 0x%016lx",
			(uint64_t)sdpp->mem_offset,
			(uint64_t)base);
	/* First pages are descriptors */
	vq->vq_desc = (struct vring_desc *)base;
	base += vq->vq_qsize * sizeof(struct vring_desc);

	/* Then avail ring */
	vq->vq_avail = (struct vring_avail *)base;
	DDBG("vq->vq_avail addr 0x%016lx", (uint64_t)&vq->vq_avail);
	base += (2 + vq->vq_qsize + 1) * sizeof(uint16_t);

	/* Then it's rounded up to the next page */
	DDBG("base 0x%016lx", (uint64_t)base);
	base = (uint8_t *)roundup2((uintptr_t)base, VRING_ALIGN);
	DDBG("base aligned 0x%016lx", (uint64_t)base);

	/* And the last pages are the used ring */
	vq->vq_used = (struct vring_used *)base;
	DDBG("vq->vq_used->idx addr 0x%016lx",
			(uint64_t)&vq->vq_used->idx);

	/* Mark queue as allocated, and start at 0 when we use it. */
	vq->vq_flags = VQ_ALLOC;
	vq->vq_last_avail = 0;

	return (0);
}

static bool
vtblk_mod_init(pism_module_t *mod)
{

	DDBG("called");

	g_vtblk_debug = getenv("CHERI_DEBUG_VIRTIO_BLOCK");

	DDBG("returned");
	return (true);
}

static bool
vtblk_dev_init(pism_device_t *dev)
{
	struct vtblk_private *sdpp;
	struct dram_private *dpp;
	const char *option_path;
	uint64_t length;
	struct stat sb;
	int fd;

	DDBG("called for mapping at %jx, length %jx", dev->pd_base,
	    dev->pd_length);

	assert(dev->pd_base % PISM_DATA_BYTES == 0);
	assert(dev->pd_length % PISM_DATA_BYTES == 0);

	/*
	 * Query and validate options before doing any allocation.
	 */
	if (!(pism_device_option_get(dev, VTBLK_OPTION_PATH, &option_path)))
		option_path = NULL;
	if (option_path == NULL) {
		warnx("%s: option path required on device %s", __func__,
		    dev->pd_name);
		return (false);
	}

	assert(dev->pd_perms & \
		(PISM_PERM_ALLOW_FETCH | PISM_PERM_ALLOW_STORE));
	fd = open(option_path, O_RDWR);
	if (fd < 0) {
		warn("%s: open of %s failed on device %s", __func__,
		    option_path, dev->pd_name);
		return (false);
	}

	/*
	 * We can't handle live resize on images, and support only
	 * even multiples of 512 byte sector-size.
	 */
	if (fstat(fd, &sb) < 0) {
		warn("%s: fstat of %s failed on device %s", __func__,
		    option_path, dev->pd_name);
		close(fd);
		return (false);
	}
	length = sb.st_size;
	sdpp = calloc(1, sizeof(*sdpp));
	if (sdpp == NULL) {
		warn("%s: calloc", __func__);
		close(fd);
		return (false);
	}
	sdpp->sdp_imagefile = fd;
	sdpp->sdp_reqfifo_empty = true;
	sdpp->sdp_length = length;
	sdpp->sdp_delay = 0;
	sdpp->dev = dev;
	sdpp->intr = 0;
	sdpp->cfg = malloc(sizeof(struct virtio_blk_config));
	dev->pd_private = sdpp;

	dpp = pism_dev_get_private(PISM_BUSNO_MEMORY, "dram0");
	if (!dpp)
		return (false);
	sdpp->mem_offset = (uint64_t)dpp->dp_data;
	DDBG("mem_offset 0x%016lx", (uint64_t)sdpp->mem_offset);

	virtio_init(sdpp);

	DDBG("returned");
	return (true);
}

static bool
vtblk_dev_interrupt_get(pism_device_t *dev)
{
	struct vtblk_private *sdpp;
	bool ret;

	sdpp = dev->pd_private;
	assert(sdpp != NULL);

	/*
	 * If interrupts are requested, then poll to determine whether they
	 * should fire.
	 */
	ret = false;
	if (dev->pd_irq != PISM_IRQ_NONE) {
		if (sdpp->intr == 1) {
			ret = true;
		}
	}

	DDBG("returned: %d", ret);
	return (ret);
}

static bool
vtblk_dev_request_ready(pism_device_t *dev, pism_data_t *req)
{
	struct vtblk_private *sdpp;

	DDBG("called");

	sdpp = dev->pd_private;
	assert(sdpp != NULL);

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		return (true);

	case PISM_ACC_FETCH:
		return (sdpp->sdp_reqfifo_empty);

	default:
		assert(0);
	}
}

static int
vtblk_rdwr(struct vtblk_private *sdpp, struct iovec *iov,
        int cnt, int offset, int operation, int iolen)
{
	int error;

	if (operation == 0) { /* Read */
		error = preadv(sdpp->sdp_imagefile, iov, cnt, offset);
		DDBG("preadv cnt %d offset %d err %d\n", cnt, offset, error);

	} else { /* Write */
		error = pwritev(sdpp->sdp_imagefile, iov, cnt, offset);
		DDBG("pwritev cnt %d offset %d err %d", cnt, offset, error);
	}

	return (error);
}

static void
vtblk_proc(struct vtblk_private *sdpp, struct vqueue_info *vq)
{
	struct iovec iov[VTBLK_MAXSEGS + 2];
	uint16_t flags[VTBLK_MAXSEGS + 2];
	struct virtio_blk_outhdr *vbh;
	struct iovec *tiov;
	uint8_t *status;
	off_t offset;
	int iolen;
	int type;
	int i, n;
	int err;

	DDBG("called");

	n = vq_getchain(sdpp->mem_offset, vq, iov,
		VTBLK_MAXSEGS + 2, flags);

	DDBG("n %d\n", n);

	tiov = getcopy(iov, n);
	vbh = iov[0].iov_base;

	status = iov[n-1].iov_base;

	type = be32toh(vbh->type) & ~VIRTIO_BLK_T_BARRIER;
	offset = be64toh(vbh->sector) * DEV_BSIZE;

	iolen = 0;
	for (i = 1; i < (n-1); i++) {
		iolen += iov[i].iov_len;
	}

	switch (type) {
	case VIRTIO_BLK_T_OUT:
	case VIRTIO_BLK_T_IN:
		err = vtblk_rdwr(sdpp, tiov + 1, i - 1,
			offset, type, iolen);
		break;
	case VIRTIO_BLK_T_GET_ID:
		/* Assume a single buffer */
		strlcpy(iov[1].iov_base, sdpp->ident,
		    MIN(iov[1].iov_len, sizeof(sdpp->ident)));
		err = 0;
		break;
	case VIRTIO_BLK_T_FLUSH:
		/* Possible? */
	default:
		err = -ENOSYS;
		break;
	}

	if (err < 0) {
		if (err == -ENOSYS) {
			*status = VIRTIO_BLK_S_UNSUPP;
		} else
			*status = VIRTIO_BLK_S_IOERR;
	} else
		*status = VIRTIO_BLK_S_OK;

	free(tiov);
	vq_relchain(vq, iov, n, 1);
}

static int
vtblk_notify(struct vtblk_private *sdpp)
{
	struct vqueue_info *vq;
	int queue;
	int reg;
	uint8_t *data;

	DDBG("called");

	data = (uint8_t *)&sdpp->mmio_data;

	vq = &sdpp->vs_queues[0];
	if (!vq_ring_ready(vq))
		return (0);

	reg = *(volatile uint16_t *)(data + VIRTIO_MMIO_QUEUE_NOTIFY);
	queue = be16toh(reg);

	/* We support single queue only */
	assert(queue == 0);

	/* Process new descriptors */
	vq = &sdpp->vs_queues[queue];

	DDBG("vq->vq_used addr 0x%016lx", (uint64_t)&vq->vq_used);
	DDBG("vq->vq_save_used addr 0x%016lx", (uint64_t)&vq->vq_save_used);
	DDBG("vq->vq_used->idx 0x%016lx", (uint64_t)&vq->vq_used->idx);
	vq->vq_save_used = be16toh(vq->vq_used->idx);

	while (vq_has_descs(vq))
		vtblk_proc(sdpp, vq);

	/* Schedule interrupt if required */
	if ((be16toh(vq->vq_avail->flags) & VRING_AVAIL_F_NO_INTERRUPT) == 0) {
		reg = htobe32(VIRTIO_MMIO_INT_VRING);
		*(volatile uint32_t *)(data + VIRTIO_MMIO_INTERRUPT_STATUS) = reg;
		sdpp->intr = 1;
	}

	return (0);
}

static void
vtblk_dev_request_put(pism_device_t *dev, pism_data_t *req)
{
	struct vtblk_private *sdpp;
	uint64_t addr;
	uint8_t *d;
	int data;
	int offs;
	int i;
	int w;

	w = 0;
	offs = 0;
	d = (uint8_t *)&data;
	DDBG("called");

	sdpp = dev->pd_private;
	assert(sdpp != NULL);

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		addr = PISM_DEV_REQ_ADDR(dev, req);
		DDBG("PISM_ACC_STORE addr 0x%016lx", addr);

		for (i = 0; i < PISM_DATA_BYTES; i++) {
			if (!PISM_REQ_BYTEENABLED(req, i))
				continue;
			DDBG("PISM_ACC_STORE addr + %d = 0x%016lx, data 0x%02x",
				i, addr + i, PISM_REQ_BYTE(req, i));
			if (!offs)
				offs = (addr + i);
			*d++ = PISM_REQ_BYTE(req, i);
			w++;

			assert(addr + i < sizeof(sdpp->mmio_data));
			sdpp->mmio_data[addr + i] = PISM_REQ_BYTE(req, i);
		}
		DDBG("offs is 0x%08x width %d", offs, w);

		switch (offs) {
		case VIRTIO_MMIO_QUEUE_NOTIFY:
			vtblk_notify(sdpp);
			break;
		case VIRTIO_MMIO_QUEUE_PFN:
			vq_init(sdpp);
			break;
		case VIRTIO_MMIO_INTERRUPT_ACK:
			sdpp->intr = 0;
		default:
			break;
		}

		break;

	case PISM_ACC_FETCH:
		addr = PISM_DEV_REQ_ADDR(dev, req);
		DDBG("PISM_ACC_FETCH addr 0x%016lx", addr);

		assert(sdpp->sdp_reqfifo_empty);
		memcpy(&sdpp->sdp_reqfifo, req, sizeof(sdpp->sdp_reqfifo));
		sdpp->sdp_reqfifo_empty = false;
		sdpp->sdp_replycycle = 
			pism_cycle_count_get(dev->pd_busno) + sdpp->sdp_delay;
		break;

	default:
		assert(0);
	}

	DDBG("returned");
}

static bool
vtblk_dev_response_ready(pism_device_t *dev)
{
	struct vtblk_private *sdpp;
	bool ret;

	DDBG("called");

	sdpp = dev->pd_private;
	assert(sdpp != NULL);

	/*
	 * Implement delay: don't allow the reply to a request to come out
	 * before the scheduled reply cycle.
	 */
	if (sdpp->sdp_replycycle <= pism_cycle_count_get(dev->pd_busno))
		ret = !sdpp->sdp_reqfifo_empty;
	else
		ret = false;

	ret = true;

	DDBG("returned: %d", ret);
	return (ret);
}

static pism_data_t
vtblk_dev_response_get(pism_device_t *dev)
{
	struct vtblk_private *sdpp;
	pism_data_t *req;
	uint64_t addr;
	int i;

	DDBG("called");

	sdpp = dev->pd_private;
	assert(sdpp != NULL);

	assert(!sdpp->sdp_reqfifo_empty);
	sdpp->sdp_reqfifo_empty = true;
	req = &sdpp->sdp_reqfifo;

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		/* XXXRW: This shouldn't happen, but perhaps does. */
		assert(0);
		break;

	case PISM_ACC_FETCH:
		addr = PISM_DEV_REQ_ADDR(dev, req);
		DDBG("PISM_ACC_FETCH addr 0x%016lx", addr);

		for (i = 0; i < PISM_DATA_BYTES; i++) {
			assert(addr + i >= 0 && addr + i <
			    sizeof(sdpp->mmio_data));

			if (!PISM_REQ_BYTEENABLED(req, i))
				continue;

			PISM_REQ_BYTE(req, i) = sdpp->mmio_data[addr + i];

			DDBG("PISM_ACC_FETCH addr + %d = 0x%02x",
				i, sdpp->mmio_data[addr + i]);
		}
		break;

	default:
		assert(0);
	}
	return (*req);
}

static bool
vtblk_dev_addr_valid(pism_device_t *dev, pism_data_t *req)
{

	return (true);
}

static const char *vtblk_option_list[] = {
	VTBLK_OPTION_PATH,
	NULL
};

PISM_MODULE_INFO(vtblk_module) = {
	.pm_name = "virtio_block",
	.pm_option_list = vtblk_option_list,
	.pm_mod_init = vtblk_mod_init,
	.pm_dev_init = vtblk_dev_init,
	.pm_dev_interrupt_get = vtblk_dev_interrupt_get,
	.pm_dev_request_ready = vtblk_dev_request_ready,
	.pm_dev_request_put = vtblk_dev_request_put,
	.pm_dev_response_ready = vtblk_dev_response_ready,
	.pm_dev_response_get = vtblk_dev_response_get,
	.pm_dev_addr_valid = vtblk_dev_addr_valid,
};
