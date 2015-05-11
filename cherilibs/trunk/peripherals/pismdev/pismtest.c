/*-
 * Copyright (c) 2012 Robert N. M. Watson
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

/*-
 * Simple PISM test program that attaches a PISM bus.
 *
 * TODO:
 * 1. Do test I/O to/from an unused physical address.  Make sure it fails.
 * 2. Do test I/O to/from DRAM.  Make sure it succeeds.
 * 3. Do test I/O to/from the UART.  Make sure it succeeds.
 *
 * More generally:
 * - It would be nice if we could include the config file inline as a C string
 *   so that we could generate a config string using the same address
 *   constants we later use for I/O.
 * - It would be great if UART could be configured to use a file descriptor
 *   so that we could test for the desired characters in both directions.
 */

#include <assert.h>
#include <endian.h>
#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

#include "pismdev/pism.h"

/*
 * Errors for PISM memory access.
 */
#define	PISMTEST_SUCCESS		0	/* Succeeded. */
#define	PISMTEST_ERROR_INVALID_ADDR	1	/* Address was invalid. */
#define	PISMTEST_ERROR_TIMEOUT		2	/* Request timed out. */

#define	PISMTEST_MAXWAIT		10	/* Wait up to 10 cycles. */

static int
pismtest_request(uint8_t busno, pism_data_t *req)
{
	int i, ret;

	ret = false;
	for (i = 0; i < PISMTEST_MAXWAIT; i++) {
		ret = pism_request_ready(busno, req);
		if (ret)
			break;
	}
	if (!ret)
		return (PISMTEST_ERROR_TIMEOUT);
	pism_request_put(busno, req);
	return (PISMTEST_SUCCESS);
}

static int
pismtest_response(uint8_t busno, pism_data_t *req)
{
	int i, ret;

	ret = false;
	for (i = 0; i < PISMTEST_MAXWAIT; i++) {
		ret = pism_response_ready(busno);
		pism_cycle_tick(busno);
		if (ret)
			break;
	}
	if (!ret)
		return (PISMTEST_ERROR_TIMEOUT);
	*req = pism_response_get(busno);
	return (PISMTEST_SUCCESS);
}

static int
pismtest_mem_fetch8(uint8_t busno, uint64_t addr, uint8_t *vp)
{
	pism_data_t pd;
	u_int offset;
	int ret;

	offset = addr % PISM_DATA_BYTES;

	memset(&pd, 0x00, sizeof(pd));
	pd.pd_int.pdi_acctype = PISM_ACC_FETCH;
	pd.pd_int.pdi_addr = addr - offset;
	pd.pd_int.pdi_byteenable = 1 << offset;
	if (!pism_addr_valid(busno, &pd))
		return (PISMTEST_ERROR_INVALID_ADDR);

	memset(&pd, 0x00, sizeof(pd));
	pd.pd_int.pdi_acctype = PISM_ACC_FETCH;
	pd.pd_int.pdi_addr = addr - offset;
	pd.pd_int.pdi_byteenable = 1 << offset;
	ret = pismtest_request(busno, &pd);
	if (ret != PISMTEST_SUCCESS)
		return (ret);

	memset(&pd, 0x00, sizeof(pd));
	ret = pismtest_response(busno, &pd);
	if (ret != PISMTEST_SUCCESS)
		return (ret);
	*vp = pd.pd_int.pdi_data[offset];
	return (PISMTEST_SUCCESS);
}

static int
pismtest_mem_store8(uint8_t busno, uint64_t addr, uint8_t v)
{
	pism_data_t pd;
	u_int offset;

	offset = addr % PISM_DATA_BYTES;

	memset(&pd, 0x00, sizeof(pd));
	pd.pd_int.pdi_acctype = PISM_ACC_STORE;
	pd.pd_int.pdi_addr = addr - offset;
	pd.pd_int.pdi_byteenable = 1 << offset;
	if (!pism_addr_valid(busno, &pd))
		return (PISMTEST_ERROR_INVALID_ADDR);

	memset(&pd, 0x00, sizeof(pd));
	pd.pd_int.pdi_acctype = PISM_ACC_STORE;
	pd.pd_int.pdi_addr = addr - offset;
	pd.pd_int.pdi_byteenable = 1 << offset;
	pd.pd_int.pdi_data[offset] = v;
	return (pismtest_request(busno, &pd));
}

#include <stdio.h>

int
main(int argc, char *argv[])
{
	int ret;
	uint8_t b;

	assert(pism_init(0));

	/*
	 * Write a byte to the UART.
	 *
	 * XXXRW: It would be quite nice if we coudl configure the UART to
	 * output to a pipe so that we could read the pipe and check the byte.
	 */
	ret = pismtest_mem_store8(PISM_BUSNO_PERIPHERAL, 0x7f000000, 0x52);
	assert(ret == PISMTEST_SUCCESS);
 
	/*
	 * Attempt to store, and then fetch, a byte from DRAM.
	 */
	ret = pismtest_mem_store8(PISM_BUSNO_MEMORY, 0x10000, 0x5e);
	assert(ret == PISMTEST_SUCCESS);

	ret = pismtest_mem_fetch8(PISM_BUSNO_MEMORY, 0x10000, &b);
	assert(ret == PISMTEST_SUCCESS);
	assert(b == 0x5e);

	exit(0);
}
