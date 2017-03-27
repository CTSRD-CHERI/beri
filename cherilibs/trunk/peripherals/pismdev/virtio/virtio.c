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

#include "virtio_mmio.h"
#include "virtio_blk.h"
#include "virtio_ids.h"
#include "virtio_config.h"
#include "virtio_ring.h"
#include "virtio.h"

int
vq_ring_ready(struct vqueue_info *vq)
{

	return (vq->vq_flags & VQ_ALLOC);
}

int
vq_has_descs(struct vqueue_info *vq)
{

	return (vq_ring_ready(vq) && vq->vq_last_avail !=
		be16toh(vq->vq_avail->idx));
}

void *
paddr_map(uint64_t offset, uint64_t phys, int size)
{
	void *ret;

	ret = (void *)(offset + phys);

	return (ret);
}

void
paddr_unmap(void *phys, uint32_t size)
{

}

static inline void
_vq_record(uint64_t offs, int i, volatile struct vring_desc *vd,
	struct iovec *iov, int n_iov, uint16_t *flags)
{

	if (i >= n_iov)
		return;

	iov[i].iov_base = paddr_map(offs, be64toh(vd->addr),
				be32toh(vd->len));
	iov[i].iov_len = be32toh(vd->len);
	if (flags != NULL)
		flags[i] = be16toh(vd->flags);
}

int
vq_getchain(uint64_t offs, struct vqueue_info *vq,
	struct iovec *iov, int n_iov, uint16_t *flags)
{
	volatile struct vring_desc *vdir, *vindir, *vp;
	int idx, ndesc;
	int head, next;
	int i;

	idx = vq->vq_last_avail;
	ndesc = (be16toh(vq->vq_avail->idx) - idx);
	if (ndesc == 0)
		return (0);

	head = be16toh(vq->vq_avail->ring[idx & (vq->vq_qsize - 1)]);
	next = head;

	for (i = 0; i < VQ_MAX_DESCRIPTORS; next = be16toh(vdir->next)) {
		vdir = &vq->vq_desc[next];
		if ((be16toh(vdir->flags) & VRING_DESC_F_INDIRECT) == 0) {
			_vq_record(offs, i, vdir, iov, n_iov, flags);
			i++;
		} else {
			vindir = paddr_map(offs, be64toh(vdir->addr),
					be32toh(vdir->len));
			next = 0;
			for (;;) {
				vp = &vindir[next];
				_vq_record(offs, i, vp, iov, n_iov, flags);
				i+=1;
				if ((be16toh(vp->flags) & \
					VRING_DESC_F_NEXT) == 0)
					break;
				next = be16toh(vp->next);
			}
			paddr_unmap((void *)vindir, be32toh(vdir->len));
		}

		if ((be16toh(vdir->flags) & VRING_DESC_F_NEXT) == 0)
			return (i);
	}

	return (i);
}

void
vq_relchain(struct vqueue_info *vq, struct iovec *iov, int n, uint32_t iolen)
{
	volatile struct vring_used_elem *vue;
	volatile struct vring_used *vu;
	uint16_t head, uidx, mask;
	int i;

	mask = vq->vq_qsize - 1;
	vu = vq->vq_used;
	head = be16toh(vq->vq_avail->ring[vq->vq_last_avail++ & mask]);

	uidx = be16toh(vu->idx);
	vue = &vu->ring[uidx++ & mask];
	vue->id = htobe32(head);

	vue->len = htobe32(iolen);
	vu->idx = htobe16(uidx);

	/* Clean up */
	for (i = 0; i < n; i++) {
		paddr_unmap((void *)iov[i].iov_base, iov[i].iov_len);
	}
}

int
setup_offset(uint32_t dev, uint32_t *offset)
{

	*offset = 0;

	return (0);
}

struct iovec *
getcopy(struct iovec *iov, int n)
{
	struct iovec *tiov;
	int i;

	tiov = malloc(n * sizeof(struct iovec));
	for (i = 0; i < n; i++) {
		tiov[i].iov_base = iov[i].iov_base;
		tiov[i].iov_len = iov[i].iov_len;
	}

	return (tiov);
}
