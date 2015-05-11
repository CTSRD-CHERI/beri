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

/*
 * This file contains PISM utility functions to configure and implement PISM
 * devices.
 */

#include <sys/queue.h>

#include <assert.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pismdev/pism.h"

static const char *pism_option_list[] = {
	PISM_DEVICE_OPTION_ADDR,
	PISM_DEVICE_OPTION_LENGTH,
	PISM_DEVICE_OPTION_PERMS,
	PISM_DEVICE_OPTION_IRQ,
	NULL
};

/*
 * Check whether an option is supported for a module -- either it should
 * appear on the global option list, or the per-module list.
 */
static bool
pism_device_option_valid(pism_module_t *mod, const char *optname)
{
	const char **s;

	/*
	 * First, check the global option list.
	 */
	for (s = pism_option_list; *s != NULL; s++) {
		if (strcmp(optname, *s) == 0)
			return (true);
	}

	/*
	 * Then, check the per-module option list.
	 */
	if (mod->pm_option_list != NULL) {
		for (s = mod->pm_option_list; *s != NULL; s++) {
			if (strcmp(optname, *s) == 0)
				return (true);
		}
	}

	return (false);
}

/*
 * Add an option to a device.
 */
void
pism_device_option_add(pism_device_t *dev, const char *optname,
    const char *optval)
{
	struct pism_device_option *pdop;

	pdop = calloc(1, sizeof(*pdop));
	assert(pdop != NULL);
	pdop->pdo_optname = strdup(optname);
	assert(pdop->pdo_optname != NULL);
	pdop->pdo_optval = strdup(optval);
	assert(pdop->pdo_optval != NULL);
	TAILQ_INSERT_TAIL(&dev->pd_options, pdop, pdo_entries);
}

/*
 * Find an option on a device.
 */
bool
pism_device_option_get(pism_device_t *dev, const char *optname,
    const char **optvalp)
{
	struct pism_device_option *pdop;

	TAILQ_FOREACH(pdop, &dev->pd_options, pdo_entries) {
		if (strcmp(pdop->pdo_optname, optname) == 0) {
			if (optvalp != NULL)
				*optvalp = pdop->pdo_optval;
			return (true);
		}
	}
	return (false);
}

bool
pism_device_option_parse_bool(pism_device_t *dev, const char *optval,
    bool *boolp)
{

	if (strcmp(optval, "yes") == 0 || strcmp(optval, "true") == 0) {
		*boolp = true;
		return (true);
	} else if (strcmp(optval, "no") == 0 || strcmp(optval, "false")
	     == 0) {
		*boolp = false;
		return (true);
	}
	return (false);
}

bool
pism_device_option_parse_longlong(pism_device_t *dev, const char *optval,
    long long *llp)
{
	long long ll;
	char *endp;

	ll = strtoll(optval, &endp, 0);
	if (ll == LLONG_MIN || ll == LLONG_MAX)
		return (false);
	if (*endp != '\0')
		return (false);
	*llp = ll;
	return (true);
}

/*
 * Functions to interpret core PISM device options.
 */
static bool
pism_device_option_finalise_addr(pism_device_t *dev)
{
	long long ll;
	const char *optval;

	if (!pism_device_option_get(dev, PISM_DEVICE_OPTION_ADDR, &optval))
		return (false);
	if (!pism_device_option_parse_longlong(dev, optval, &ll))
		return (false);
	if (ll < 0)
		return (false);
	dev->pd_base = ll;
	return (true);
}

static bool
pism_device_option_finalise_length(pism_device_t *dev)
{
	long long ll;
	const char *optval;

	if (!pism_device_option_get(dev, PISM_DEVICE_OPTION_LENGTH, &optval))
		return (false);
	if (!pism_device_option_parse_longlong(dev, optval, &ll))
		return (false);
	if (ll < 0)
		return (false);
	dev->pd_length = ll;
	return (true);
}

/*
 * Require that perm masks either be FETCH|STORE|CREATE, FETCH|STORE
 * or FETCH.  Right now, there's no obvious reason to allow other
 * masks.
 */
static inline bool
pism_perms_valid(uint32_t perms)
{
	const uint32_t fetch = PISM_PERM_ALLOW_FETCH;
	const uint32_t fetch_store = fetch | PISM_PERM_ALLOW_STORE;
	const uint32_t fetch_store_create = fetch_store | PISM_PERM_ALLOW_CREATE;
	return (perms == fetch || perms == fetch_store || 
			perms == fetch_store_create);
}

static bool
pism_device_option_finalise_perms(pism_device_t *dev)
{
	const char *optval;
	uint32_t perms;

	/*
	 * Unlike other options, "perms" has a default value of allowing both
	 * fetch and store.
	 */
	if (!pism_device_option_get(dev, PISM_DEVICE_OPTION_PERMS, &optval))
		optval = PISM_PERM_ALLOW_DEFAULT_STR;
	perms = 0;
	for (; *optval != '\0'; optval++) {
		switch (*optval) {
		case PISM_PERM_ALLOW_FETCH_CHR:
		case PISM_PERM_ALLOW_READ_CHR:
			perms |= PISM_PERM_ALLOW_FETCH;
			break;

		case PISM_PERM_ALLOW_STORE_CHR:
		case PISM_PERM_ALLOW_WRITE_CHR:
			perms |= PISM_PERM_ALLOW_STORE;
			break;

		case PISM_PERM_ALLOW_CREATE_CHR:
			perms |= PISM_PERM_ALLOW_CREATE;
			break;

		default:
			return (false);
		}
	}

	if (!pism_perms_valid(perms))
		return (false);
	dev->pd_perms = perms;
	return (true);
}

static int
pism_device_option_finalise_irq(pism_device_t *dev)
{
	const char *optval;
	long long ll;

	/*
	 * Default value will be used if no "irq" field is defined, indicating
	 * no IRQ is used.
	 */
	if (!pism_device_option_get(dev, PISM_DEVICE_OPTION_IRQ, &optval)) {
		dev->pd_irq = PISM_IRQ_NONE;
		return (true);
	}
	if (!pism_device_option_parse_longlong(dev, optval, &ll))
		return (false);
	if (ll < PISM_IRQ_MIN || ll > PISM_IRQ_MAX)
		return (false);
	dev->pd_irq = ll;
	return (true);
}

/*
 * Check that all options defined on a device are valid; interpret any core
 * PISM options.  This must be called before the device initialisation
 * routine, so that these values are available to the module.
 */
bool
pism_device_options_finalise(pism_device_t *dev)
{
	struct pism_device_option *pdop;

	/*
	 * Make sure that all defines options are allowed on this device.
	 */
	TAILQ_FOREACH(pdop, &dev->pd_options, pdo_entries) {
		if (pism_device_option_valid(dev->pd_mod, pdop->pdo_optname))
			continue;
		fprintf(stderr, "%s: invalid option %s on device %s\n",
		    __func__, pdop->pdo_optname, dev->pd_name);
		return (false);
	}

	/*
	 * Find and evaluate various core PISM options.
	 */
	if (!pism_device_option_finalise_addr(dev)) {
		fprintf(stderr,
		    "%s: invalid or missing addr option on device %s\n",
		    __func__, dev->pd_name);
		return (false);
	}
	if (!pism_device_option_finalise_length(dev)) {
		fprintf(stderr,
		    "%s: invalid or missing length option on device %s\n",
		    __func__, dev->pd_name);
		return (false);
	}
	if (!pism_device_option_finalise_perms(dev)) {
		fprintf(stderr,
		    "%s: invalid or missing perms option on device %s\n",
		    __func__, dev->pd_name);
		return (false);
	}
	if (!pism_device_option_finalise_irq(dev)) {
		fprintf(stderr,
		    "%s: invalid irq option on device %s\n", __func__,
		    dev->pd_name);
		return (false);
	}
	return (true);
}
