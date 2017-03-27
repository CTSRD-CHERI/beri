/*-
 * Copyright (c) 2013 Bjoern A. Zeeb
 * Copyright (c) 2015 Theo Markettos
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
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

#include <sys/types.h>

#ifdef __FreeBSD__
#include <sys/endian.h>
#elif __APPLE__
#include "macosx.h"
#else
#include <endian.h>
#endif

#include <inttypes.h>
#include <stdio.h>
#include <unistd.h>

#ifdef __FreeBSD__
#include <sys/endian.h>
#endif

#include "../../include/cheri_debug.h"
#include "cherictl.h"

#define	PIC_INTR_NUM			1024
#define	PIC_CONFIG_BASE		0x900000007f804000
#define	PIC_CONFIG_WIDTH		8
#define	PIC_MIPS_INTR_MASK		0x00000007
#define	PIC_THREAD_ID_MASK		0x07ffff00 /* currently not defined. */
#define	PIC_THREAD_ID_SHIFT		8
#define	PIC_INTR_ENABLE_MASK		0x80000000
#define	PIC_IP_READ_BASE	(PIC_CONFIG_BASE + \
				PIC_INTR_NUM * PIC_CONFIG_WIDTH)
#define PIC_MULTI_SPACING		0x4000

/* 
 * Given we currently do not do pipelined reads this is rather slow and
 * we really do not want to read all 1024 possible interrupts.  Limit it
 * to about the number we implement for now.
 */
#define	PIC_DUMP_MAX			16

static uint64_t intr_fired[PIC_INTR_NUM / (sizeof(uint64_t) * 8)];

static void
print_pic_entry(int i, uint64_t addr, uint64_t v)
{
	uint64_t fired;
	uint32_t enabled, irq, threadid;


	/* Only print disabled IRQs if quietflag is not set. */
	enabled = v & PIC_INTR_ENABLE_MASK;
	if (quietflag && enabled == 0)
		return;

	irq = v & PIC_MIPS_INTR_MASK;
	threadid = (v & PIC_THREAD_ID_MASK) >> PIC_THREAD_ID_SHIFT;
	fired = (intr_fired[i / (sizeof(uint64_t) * 8)] >>
	    (i % (sizeof(uint64_t) * 8))) & 0x1;

	printf("%04d 0x%016" PRIx64 " 0x%016" PRIx64 " mapped to IRQ %u, thread ID 0x%08x, %s"
	    "%s\n", i, addr, v, irq, threadid, enabled ? "enabled" : "disabled",
	    fired ? ", fired" : "");
}

int
berictl_dumppic(struct beri_debug *bdp, int pic_id)
{
	uint64_t v;
	int i, ret;
	uint8_t excode;

	if (!quietflag)
		printf("PIC %d status:\n", pic_id);

	/* Pause CPU */
	ret = berictl_pause(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/* Read the current snapshot status of IRQs fired. */
	if (!quietflag)
		printf("Gathering snapshot of IRQs fired.\n");
	for (i = 0; ret == BERI_DEBUG_SUCCESS &&
	    i < (PIC_INTR_NUM / (sizeof(uint64_t) * 8)); i++) {
		ret = beri_debug_client_ld(bdp,
		    htobe64(PIC_IP_READ_BASE + pic_id * PIC_MULTI_SPACING +
			i * sizeof(uint64_t)),
		    &intr_fired[i], &excode);
		switch (ret) {
		case BERI_DEBUG_ERROR_EXCEPTION:
			fprintf(stderr, "0x%04d 0x%016jx lwu Exception!  "
			    "Code = 0x%x\n", i,
			    /* XXX: should this be PIC_IP_READ_BASE ? */
			    PIC_CONFIG_BASE + pic_id * PIC_MULTI_SPACING +
				i * sizeof(uint64_t), excode);
			break;
		case BERI_DEBUG_SUCCESS:
			intr_fired[i] = be64toh(intr_fired[i]);
			break;
		}
	}

	/* Read the IRQ mappings and meta data. */
	if (!quietflag)
		printf("IRQ mappings and status.\n");
	for (i = 0; ret == BERI_DEBUG_SUCCESS && i < PIC_DUMP_MAX; i++) {
		ret = beri_debug_client_ld(bdp,
		    htobe64(PIC_CONFIG_BASE + pic_id * PIC_MULTI_SPACING +
			i * 8), &v, &excode);
		switch (ret) {
		case BERI_DEBUG_ERROR_EXCEPTION:
			fprintf(stderr, "0x%04d 0x%016jx lwu Exception!  "
			    "Code = 0x%x\n", i, PIC_CONFIG_BASE + 
				pic_id * PIC_MULTI_SPACING + i*8, excode);
			break;
		case BERI_DEBUG_SUCCESS:
			v = be64toh(v);
			break;
		}
		print_pic_entry(i, PIC_CONFIG_BASE + pic_id * PIC_MULTI_SPACING
		    + i * 8, v);
	}

	/* Resume CPU */
	if (berictl_resume(bdp) != BERI_DEBUG_SUCCESS) {
		fprintf(stderr, "Resuming CPU failed. You are screwed.\n");
		ret = BERI_DEBUG_ERROR_EXCEPTION;
	}

	return (ret);
}

/* end */
