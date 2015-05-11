/*-
 * Copyright (c) 2011 Jonathan Woodruff
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2011-2012 Philip Paeps
 * Copyright (c) 2012-2014 Robert N. M. Watson
 * Copyright (c) 2013 Colin Rothwell
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
#define _XOPEN_SOURCE 

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/queue.h>
#include <sys/stat.h>

#include <assert.h>
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

/*-
 * PISM simulation of DRAM.  Regions of DRAM may be backed by zero-filled
 * memory, or memory mapped from a file.  A delay, in cycles, may be specified
 * for how quickly memory operations should take.
 *
 * TODO:
 * - Allow configurable pipeline depth -- currently that depth is hard-coded
 *   at 1 (the actual minimum given the protocol used to talk to DRAM).
 * - Allow custom fill words of varying lengths, perhaps named "fill1",
 *   "fill2", "fill4", and "fill8".
 */

static pism_mod_init_t			dram_mod_init;
static pism_dev_request_ready_t		dram_dev_request_ready;
static pism_dev_request_put_t		dram_dev_request_put;
static pism_dev_response_ready_t	dram_dev_response_ready;
static pism_dev_response_get_t		dram_dev_response_get;
static pism_dev_addr_valid_t		dram_dev_addr_valid;

/*
 * Data structure describing per-DRAM instance fields, hung off of
 * pism_device_t->pd_private.  Once we support pipelining, dp_reqfifo will
 * need to actually be a FIFO, and the reply cycle will be per-entry.
 */
struct dram_private {
	uint8_t		*dp_data;
	pism_data_t	 dp_reqfifo;
	bool		 dp_reqfifo_empty;
	uint		 dp_delay;
	uint64_t	 dp_replycycle;	/* Earliest cycle reply permitted. */
};

/*
 * DRAM-specific option names.
 */
#define	DRAM_OPTION_TYPE	"type"	/* DRAM mapping type. */
#define	DRAM_OPTION_PATH	"path"	/* File system path to memory map. */
#define	DRAM_OPTION_COW		"cow"	/* Enable copy-on-write. */
#define	DRAM_OPTION_DELAY	"delay"	/* Cycles each read takes. */

/*
 * Possible strings for the "type" option.
 */
#define	DRAM_TYPE_ZERO_STR	"zero"
#define	DRAM_TYPE_MMAP_STR	"mmap"

/*
 * Default options for the DRAM module.
 */
#define	DRAM_TYPE_ZERO		0
#define	DRAM_TYPE_MMAP		1
#define	DRAM_TYPE_DEFAULT	DRAM_TYPE_ZERO	/* Zero'd memory by default. */

#define	DRAM_DELAY_DEFAULT	1
#define	DRAM_DELAY_MINIMUM	1
#define	DRAM_DELAY_MAXIMUM	UINT_MAX

static char		*g_dram_debug = NULL;

#define	DDBG_MOD(...)	do	{					\
	if (g_dram_debug == NULL) {					\
		break;							\
	}								\
	printf("dram: %s(%s:%d): ", __func__, __FILE__, __LINE__);	\
	printf(__VA_ARGS__);						\
	printf("\n");							\
} while (0)

#define	DDBG(dev, ...)	do	{					\
	if (g_dram_debug == NULL) {					\
		break;							\
	}								\
	printf("%s(%s:%d) ", __func__, __FILE__, __LINE__);		\
	if ((dev) != NULL)						\
		printf("dram@%jx ", dev->pd_base);			\
	printf(__VA_ARGS__);						\
	printf("\n");							\
} while (0)

#define	ROUNDUP(x, y)	((((x) + (y) - 1)/(y)) * (y))

static bool
dram_mod_init(pism_module_t *mod)
{

	DDBG_MOD("called");

	g_dram_debug = getenv("CHERI_DEBUG_DRAM");

	DDBG_MOD("returned - %d", true);
	return (true);
}

static bool
dram_str_to_type(const char *str, int *typep)
{

	if (strcmp(str, DRAM_TYPE_ZERO_STR) == 0) {
		*typep = DRAM_TYPE_ZERO;
		return (true);
	} else if (strcmp(str, DRAM_TYPE_MMAP_STR) == 0) {
		*typep = DRAM_TYPE_MMAP;
		return (true);
	}
	return (false);
}

static bool
dram_dev_init(pism_device_t *dev)
{
	struct stat sb;
	struct dram_private *dpp;
	const char *option_type, *option_path, *option_cow, *option_delay;
	uint64_t length;
	long long delayll;
	int delay, fd, open_flags, dram_type, mmap_prot;
	bool cow_flag;

	DDBG(dev, "called for mapping at %jx, length %jx", dev->pd_base,
	    dev->pd_length);

	assert(dev->pd_base % PISM_DATA_BYTES == 0);
	assert(dev->pd_length % PISM_DATA_BYTES == 0);

	/*
	 * Query and validate options before doing any allocation.
	 */
	if (!(pism_device_option_get(dev, DRAM_OPTION_TYPE, &option_type)))
		option_type = NULL;
	if (!(pism_device_option_get(dev, DRAM_OPTION_PATH, &option_path)))
		option_path = NULL;
	if (!(pism_device_option_get(dev, DRAM_OPTION_COW, &option_cow)))
		option_cow = NULL;
	if (!(pism_device_option_get(dev, DRAM_OPTION_DELAY, &option_delay)))
		option_delay = NULL;
	if (option_type != NULL) {
		if (!(dram_str_to_type(option_type, &dram_type))) {
			warnx("%s: invalid DRAM type on device %s", __func__,
			    dev->pd_name);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
	} else
		dram_type = DRAM_TYPE_DEFAULT;
	if (option_cow != NULL) {
		if (dram_type != DRAM_TYPE_MMAP) {
			warnx("%s: unexpected cow option on device %s",
			    __func__, dev->pd_name);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
		if (!(pism_device_option_parse_bool(dev, option_cow,
		    &cow_flag))) {
			warnx("%s: invalid cow option on device %s", __func__,
			    dev->pd_name);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
	} else
		cow_flag = false;
	if (dram_type == DRAM_TYPE_MMAP && option_path == NULL) {
		warnx("%s: DRAM type mmap requires path on device %s",
		    __func__, dev->pd_name);
		DDBG(dev, "returned - %d", false);
		return (false);
	} else if (dram_type != DRAM_TYPE_MMAP && option_path != NULL) {
		warnx("%s: unexpected path option on device %s", __func__,
		    dev->pd_name);
		DDBG(dev, "returned - %d", false);
		return (false);
	}
	if (option_delay != NULL) {
		if (!pism_device_option_parse_longlong(dev, option_delay,
		    &delayll)) {
			warnx("%s: invalid delay option on device %s",
			    __func__, dev->pd_name);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
		if (delayll < DRAM_DELAY_MINIMUM) {
			warnx("%s: requested delay %lld below minimum %d on "
			    "device %s", __func__, delayll,
			    DRAM_DELAY_MINIMUM, dev->pd_name);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
		if (delayll > DRAM_DELAY_MAXIMUM) {
			warnx("%s: requested delay %lld above maximum %d on "
			    "device %s", __func__, delayll,
			    DRAM_DELAY_MAXIMUM, dev->pd_name);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
		delay = delayll;
	} else
		delay = DRAM_DELAY_DEFAULT;

	const uint32_t fetch_store_perms = (PISM_PERM_ALLOW_FETCH | 
			PISM_PERM_ALLOW_STORE);

	/*
	 * DRAM devices automatically fill out whatever space has been
	 * allocated to them during configuration.  In the future we will want
	 * to inspect additional configuration parameters here in order to
	 * allow, for example, sourcing data from a UNIX device or file.
	 */
	dpp = calloc(1, sizeof(*dpp));
	assert(dpp != NULL);
	switch (dram_type) {
	case DRAM_TYPE_ZERO:
		dpp->dp_data = calloc(1, dev->pd_length);
		assert(dpp->dp_data != NULL);
		break;

	case DRAM_TYPE_MMAP:
		switch (dev->pd_perms & fetch_store_perms) {
		case (PISM_PERM_ALLOW_FETCH | PISM_PERM_ALLOW_STORE):
			open_flags = cow_flag ? O_RDONLY : O_RDWR;
			if (dev->pd_perms & PISM_PERM_ALLOW_CREATE) {
				open_flags |= O_CREAT;
			}
			mmap_prot = PROT_READ | PROT_WRITE;
			break;

		case PISM_PERM_ALLOW_FETCH:
			open_flags = O_RDONLY;
			mmap_prot = PROT_READ;
			break;

		default:
			assert(0);
		}

		fd = open(option_path, open_flags, S_IRUSR | S_IWUSR); // user read write mode
		if (fd < 0) {
			warn("%s: open of %s failed on device %s", __func__,
			    option_path, dev->pd_name);
			free(dpp);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
		if (fstat(fd, &sb) < 0) {
			warn("%s: fstat of %s failed on device %s", __func__,
			    option_path, dev->pd_name);
			free(dpp);
			close(fd);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
		if (dev->pd_perms & PISM_PERM_ALLOW_CREATE) {
			length = ROUNDUP(dev->pd_length, PISM_DATA_BYTES);
			assert(dev->pd_perms & PISM_PERM_ALLOW_STORE);
			// Create and store should have been set together.
			if (ftruncate(fd, length) < 0) {
				warn("%s: failed to truncate file to size %lX",
					__func__, length);
			}
		} else {
			length = ROUNDUP(sb.st_size, PISM_DATA_BYTES);
		}
		if (length < dev->pd_length) {
			warnx("%s: rounding size down to %jd on device %s",
			    __func__, length, dev->pd_name);
			dev->pd_length = length;
		}
		dpp->dp_data = mmap(NULL, dev->pd_length, mmap_prot,
		    (cow_flag ? MAP_PRIVATE : MAP_SHARED), fd, 0);
		if (dpp->dp_data == MAP_FAILED) {
			warn("%s: mmap of %s on device %s failed", __func__,
			    option_path, dev->pd_name);
			free(dpp);
			close(fd);
			DDBG(dev, "returned - %d", false);
			return (false);
		}
		close(fd);
		break;

	default:
		assert(0);
	}

	dpp->dp_delay = delay;
	dpp->dp_reqfifo_empty = true;
	dev->pd_private = dpp;

	DDBG(dev, "returned - %d", true);
	return (true);
}

static bool
dram_dev_request_ready(pism_device_t *dev, pism_data_t *req)
{
	struct dram_private *dpp;

	DDBG(dev, "called - acctype %d", PISM_REQ_ACCTYPE(req));

	dpp = dev->pd_private;
	assert(dpp != NULL);

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		DDBG(dev, "returned - %d", true);
		return (true);

	case PISM_ACC_FETCH:
		DDBG(dev, "returned - %d", dpp->dp_reqfifo_empty);
		return (dpp->dp_reqfifo_empty);

	default:
		DDBG(dev, "unknown request type");
		assert(0);
	}
}

static void
dram_dev_request_put(pism_device_t *dev, pism_data_t *req)
{
	struct dram_private *dpp;
	uint64_t addr;
	int i;

	DDBG(dev, "called - acctype %d", PISM_REQ_ACCTYPE(req));

	dpp = dev->pd_private;
	assert(dpp != NULL);

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		addr = PISM_DEV_REQ_ADDR(dev, req);
		for (i = 0; i < PISM_DATA_BYTES; i++) {
			if (!PISM_REQ_BYTEENABLED(req, i))
				continue;
			assert(addr + i < dev->pd_length);
			assert(dpp->dp_data != NULL);
			dpp->dp_data[addr + i] = PISM_REQ_BYTE(req, i);
		}
		break;

	case PISM_ACC_FETCH:
		assert(dpp->dp_reqfifo_empty);
		memcpy(&dpp->dp_reqfifo, req, sizeof(dpp->dp_reqfifo));
		dpp->dp_reqfifo_empty = false;
		dpp->dp_replycycle = pism_cycle_count_get(dev->pd_busno) + dpp->dp_delay;
		break;

	default:
		assert(0);
	}

	DDBG(dev, "returned");
}

static bool
dram_dev_response_ready(pism_device_t *dev)
{
	struct dram_private *dpp;
	bool ret;

	DDBG(dev, "called");

	dpp = dev->pd_private;
	assert(dpp != NULL);

	/*
	 * Implement delay: don't allow the reply to a request to come out
	 * before the scheduled reply cycle.
	 */



	if (dpp->dp_replycycle <= pism_cycle_count_get(dev->pd_busno))
		ret = !dpp->dp_reqfifo_empty;
	else
		ret = false;

	DDBG(dev, "returned - %d", ret);
	return (ret);
}

static pism_data_t
dram_dev_response_get(pism_device_t *dev)
{
	struct dram_private *dpp;
	pism_data_t *req;
	uint64_t addr;
	int i;

	DDBG(dev, "called");

	dpp = dev->pd_private;
	assert(dpp != NULL);

	assert(!dpp->dp_reqfifo_empty);
	dpp->dp_reqfifo_empty = true;
	req = &dpp->dp_reqfifo;

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		/* XXXRW: This shouldn't happen, but perhaps does. */
		assert(0);
		break;

	case PISM_ACC_FETCH:
		addr = PISM_DEV_REQ_ADDR(dev, req);
		for (i = 0; i < PISM_DATA_BYTES; i++) {
			if (PISM_REQ_BYTEENABLED(req, i)) {
				assert(addr + i < dev->pd_length);
				PISM_REQ_BYTE(req, i) =
				    dpp->dp_data[addr + i];
			} else
				PISM_REQ_BYTE(req, i) = 0xab;	/* Filler. */
		}
		break;

	default:
		assert(0);
	}
	DDBG(dev, "returned");
	return (*req);
}

static bool
dram_dev_addr_valid(pism_device_t *dev, pism_data_t *req)
{

	DDBG(dev, "returned - %d", true);
	return (true);
}

static const char *dram_option_list[] = {
	DRAM_OPTION_TYPE,
	DRAM_OPTION_PATH,
	DRAM_OPTION_COW,
	DRAM_OPTION_DELAY,
	NULL
};

PISM_MODULE_INFO(dram_module) = {
	.pm_name = "dram",
	.pm_option_list = dram_option_list,
	.pm_mod_init = dram_mod_init,
	.pm_dev_init = dram_dev_init,
	.pm_dev_request_ready = dram_dev_request_ready,
	.pm_dev_request_put = dram_dev_request_put,
	.pm_dev_response_ready = dram_dev_response_ready,
	.pm_dev_response_get = dram_dev_response_get,
	.pm_dev_addr_valid = dram_dev_addr_valid,
};
