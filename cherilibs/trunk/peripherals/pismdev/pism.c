/*-
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2011-2012 Jonathan Woodruff
 * Copyright (c) 2011-2012 Philip Paeps
 * Copyright (c) 2011 Jonathan Anderson
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2012 SRI International
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
#include <sys/param.h>
#include <sys/queue.h>

#include <assert.h>
#include <dlfcn.h>
#include <err.h>
#include <inttypes.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pismdev/pism.h"
#include "pismdev/cheri.h"
#include "y.tab.h"

/*
 * Debugging for this file.
 */
static char	*g_pism_debug = NULL;
#define	PDBG(busno, ...)	do	{				\
	if (g_pism_debug == NULL) {					\
		break;							\
	};								\
	printf("%s(%s:%d) bus %d: ", __func__, __FILE__, __LINE__, busno); \
	printf(__VA_ARGS__);						\
	printf("\n");							\
} while (0)

/*
 * Global variables.
 */
static char *g_cheri_config;

struct pism_devices pism_devices_head[PISM_BUS_COUNT];
struct pism_devices *g_pism_devices[PISM_BUS_COUNT] = 
	{&pism_devices_head[0], &pism_devices_head[1], &pism_devices_head[2]};
struct pism_modules pism_modules_head;
struct pism_modules *g_pism_modules = &pism_modules_head;
static bool pism_modules_initialised = false;

extern FILE *yyin;
extern const char *yyfile;
extern uint8_t yybusno;
extern int yyparse(void);

/*
 * PISM-maintained cycle counter so that every device doesn't do it itself.
 */
static uint64_t pism_cycle_count[PISM_BUS_COUNT];

static bool pism_initialized[PISM_BUS_COUNT] = {false, false, false};

struct pism_module *
pism_module_lookup(const char *name)
{
	struct pism_module *pm;

	SLIST_FOREACH(pm, g_pism_modules, pm_next) {
		if (strcmp(pm->pm_name, name) == 0)
			return (pm);
	}
	return (NULL);
}

bool
pism_init(uint8_t busno)
{
	struct pism_module *pm;
	bool ret;
	const char *conf_env_name, *conf_filename;

	// XXX cr437: we should possibly have seperate ones for each bus
	// additionally, debug doesn't happen if init not called first...
	g_pism_debug = getenv("CHERI_DEBUG_PISM");

	PDBG(busno, "called");

	assert(busno == PISM_BUSNO_MEMORY || 
			busno == PISM_BUSNO_PERIPHERAL || 
			busno == PISM_BUSNO_TRACE);
	assert(!pism_initialized[busno]);

	pism_initialized[busno] = true;
	yybusno = busno;

	SLIST_INIT(g_pism_devices[busno]);
	if (!pism_modules_initialised) {
		SLIST_INIT(g_pism_modules);
		pism_modules_initialised = true;
	}

	switch (busno) {
	case PISM_BUSNO_MEMORY:
		conf_env_name = "CHERI_MEMORY_CONFIG";
		conf_filename = "./memoryconfig";
		break;
	case PISM_BUSNO_PERIPHERAL:
		conf_env_name = "CHERI_PERIPHERAL_CONFIG";
		conf_filename = "./peripheralconfig";
		break;
	case PISM_BUSNO_TRACE:
		conf_env_name = "CHERI_TRACE_CONFIG";
		conf_filename = "./traceconfig";
		break;
	default:
		assert(0); /* something's gone really badly wrong. */
	}

	g_cheri_config = getenv(conf_env_name);
	if (g_cheri_config == NULL)
		g_cheri_config = strdup(conf_filename);
	assert(g_cheri_config != NULL);
	if ((yyin = fopen(g_cheri_config, "r")) == NULL)
		err(2, "%s", g_cheri_config);
	yyfile = g_cheri_config;
	if (yyparse() != 0)
		err(3, "Couldn't parse %s", g_cheri_config);

	SLIST_FOREACH(pm, g_pism_modules, pm_next) {
		if (!pm->pm_initialised) {
			ret = pm->pm_mod_init(pm);
			if (ret != true) {
				fprintf(stderr, "Couldn't initialize module %s\n",
						pm->pm_name);
				abort();
			}
			pm->pm_initialised = true;
		}
	}

	g_cheri_config = NULL; /* use same global for trace & sim. */

	PDBG(busno, "returned %d", true);
	return (true);
}

/*
 * CHERI expects that PISM, like Avalon, will return responses to fetch
 * operations in FIFO order.  This requires PISM to remember what order
 * fetches to devices were issued in so that it can maintain that order as
 * responses are picked up.  Implement a simple FIFO to support this.
 *
 * XXXRW: Currently, CHERI ignores _read() methods, so may attempt to overflow
 * this FIFO.
 */

#define	PISM_FIFO_DEPTH		16
static pism_device_t	*pism_fifo[PISM_BUS_COUNT][PISM_FIFO_DEPTH];
static int	pism_fifo_head[PISM_BUS_COUNT], pism_fifo_tail[PISM_BUS_COUNT];

static inline int
pism_fifo_inc(int a)
{

	return ((a + 1) % PISM_FIFO_DEPTH);
}

static void
pism_fifo_enqueue(uint8_t busno, pism_device_t *dev)
{

	assert(pism_fifo_inc(pism_fifo_head[busno]) != pism_fifo_tail[busno]);
	pism_fifo[busno][pism_fifo_head[busno]] = dev;
	pism_fifo_head[busno] = pism_fifo_inc(pism_fifo_head[busno]);
}

static bool
pism_fifo_empty(uint8_t busno)
{

	return (pism_fifo_head[busno] == pism_fifo_tail[busno]);
}

static inline pism_device_t *
pism_fifo_dequeue_internal(uint8_t busno, bool dequeue)
{
	pism_device_t *dev;

	assert(pism_fifo_head[busno] != pism_fifo_tail[busno]);
	dev = pism_fifo[busno][pism_fifo_tail[busno]];
	if (dequeue)
		pism_fifo_tail[busno] = pism_fifo_inc(pism_fifo_tail[busno]);
	return (dev);
}

static pism_device_t *
pism_fifo_dequeue(uint8_t busno)
{

	return (pism_fifo_dequeue_internal(busno, true));
}

static pism_device_t *
pism_fifo_peek(uint8_t busno)
{

	return (pism_fifo_dequeue_internal(busno, false));
}

void
pism_cycle_tick(uint8_t busno)
{
	pism_device_t *dev;

	PDBG(busno, "called");

	/*
	 * Update global cycle counter. 
	 */
	pism_cycle_count[busno]++;

	SLIST_FOREACH(dev, g_pism_devices[busno], pd_next) {
		if (dev->pd_mod->pm_dev_cycle_tick != NULL)
			dev->pd_mod->pm_dev_cycle_tick(dev);
	}

	PDBG(busno, "returned");
}


uint32_t
pism_interrupt_get(uint8_t busno)
{
	pism_device_t *dev;
	uint32_t interrupts;

	PDBG(busno, "called");

	/*
	 * Walk modules and query each for an interrupt.
	 */
	interrupts = 0;
	SLIST_FOREACH(dev, g_pism_devices[busno], pd_next) {
		if (dev->pd_mod->pm_dev_interrupt_get == NULL)
			continue;
		if (dev->pd_mod->pm_dev_interrupt_get(dev) &&
		    dev->pd_irq != -1)
			interrupts |= (1 << dev->pd_irq);
	}

	PDBG(busno, "returned - %u", interrupts);
	return (interrupts);
}

/*
 * Arguably part of the PISM "device" API, but here so that symbols are
 * visible.
 */
uint64_t
pism_cycle_count_get(uint8_t busno)
{

	return (pism_cycle_count[busno]);
}

/*
 * Given a request structure, find a suitable device.  If required, request
 * address validity must be performed by the caller.
 */
static pism_device_t *
pism_dev_lookup_req(uint8_t busno, pism_data_t *req)
{
	pism_device_t *dev;
	uint64_t addr;

	addr = req->pd_int.pdi_addr;
	SLIST_FOREACH(dev, g_pism_devices[busno], pd_next) {
		if (addr >= dev->pd_base && addr + PISM_DATA_BYTES - 1 <
		    dev->pd_base + dev->pd_length)
			return (dev);
	}
	return (NULL);
}

bool
pism_request_ready(uint8_t busno, pism_data_t *req)
{
	pism_device_t *dev;
	bool response;

	PDBG(busno, "called - acctype %d addr %jx byteenable %x",
	    PISM_REQ_ACCTYPE(req), req->pd_int.pdi_addr,
	    req->pd_int.pdi_byteenable);

	if (!pism_initialized[busno]) {
		PDBG(busno, "returned - %d", false);
		return (false);
	}

	assert(req->pd_int.pdi_addr % PISM_DATA_BYTES == 0);

	/*
	 * We assert that dev is not NULL because we should only receive
	 * requests over PISM for previously validated addresses.
	 */
	dev = pism_dev_lookup_req(busno, req);
	assert(dev != NULL);

	/* Assign to variable so debug messages are in correct order. */
	response = (dev->pd_mod->pm_dev_request_ready(dev, req));

	PDBG(busno, "returned - %d", response);
	return (response);
}

void
pism_request_put(uint8_t busno, pism_data_t *req)
{
	pism_device_t *dev;

	PDBG(busno, "called - acctype %d addr %jx byteenable %x",
	    PISM_REQ_ACCTYPE(req), req->pd_int.pdi_addr,
	    req->pd_int.pdi_byteenable);
	assert(req->pd_int.pdi_addr % PISM_DATA_BYTES == 0);

	dev = pism_dev_lookup_req(busno, req);
	assert(dev != NULL);
	assert(dev->pd_mod->pm_dev_request_put != NULL);
	dev->pd_mod->pm_dev_request_put(dev, req);

	/*
	 * Enqueue this device to the FIFO so that response order is
	 * maintained across devices.
	 */
	if (PISM_REQ_ACCTYPE(req) == PISM_ACC_FETCH)
		pism_fifo_enqueue(busno, dev);

	PDBG(busno, "returned");
}

bool
pism_response_ready(uint8_t busno)
{
	pism_device_t *dev;
	bool ret;

	PDBG(busno, "called");

	if (!pism_initialized[busno]) {
		PDBG(busno, "returned");
		return (false);
	}

	if (pism_fifo_empty(busno)) {
		PDBG(busno, "returned");
		return (false);
	}

	dev = pism_fifo_peek(busno);
	assert(dev != NULL);

	assert(dev->pd_mod->pm_dev_response_ready != NULL);
	ret = dev->pd_mod->pm_dev_response_ready(dev);

	PDBG(busno, "returned - %d", ret);
	return (ret);
}

pism_data_t
pism_response_get(uint8_t busno)
{
	pism_device_t *dev;
	pism_data_t return_data;

	PDBG(busno, "called");

	/*
	 * XXXRW: We should instead fail an assertion here, as
	 * pism_response_ready() should prevent calls when PISM is not
	 * actually ready.
	 */
	if (pism_fifo_empty(busno)) {
		PDBG(busno, "Returning default response");
		memset(&return_data, 0x00, sizeof(return_data));
		return (return_data);
	}

	dev = pism_fifo_dequeue(busno);
	assert(dev != NULL);

	assert(dev->pd_mod->pm_dev_response_get != NULL);
	return_data = dev->pd_mod->pm_dev_response_get(dev);

	PDBG(busno, "Returning device response");
	return (return_data);
}

bool
pism_addr_valid(uint8_t busno, pism_data_t *req)
{
	pism_device_t *dev;
	bool ret;

	PDBG(busno, "called - %08jx", req->pd_int.pdi_addr);

	dev = pism_dev_lookup_req(busno, req);
	if (dev == NULL) {
		PDBG(busno, "returned - %d", false);
		return (false);
	}

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_FETCH:
		if (!(dev->pd_perms & PISM_PERM_ALLOW_FETCH)) {
			PDBG(busno, "returned - %d - permissions", false);
			return (false);
		}
		break;

	case PISM_ACC_STORE:
		if (!(dev->pd_perms & PISM_PERM_ALLOW_STORE)) {
			PDBG(busno, "returned - %d - permissions", false);
			return (false);
		}
		break;

	default:
		assert(0);
	}

	assert(dev->pd_mod->pm_dev_addr_valid != NULL);
	ret = dev->pd_mod->pm_dev_addr_valid(dev, req);

	PDBG(busno, "returned - %d", ret);
	return (ret);
}
