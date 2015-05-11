/*-
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2012 Philip Paeps
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
#ifndef _PISM_H_
#define	_PISM_H_

#include <sys/types.h>
#include <sys/queue.h>
#include <inttypes.h>
#include <stdbool.h>

/*
 * Number and description of PISM busses
 */
#define PISM_BUS_COUNT		3
#define PISM_BUSNO_MEMORY	0
#define PISM_BUSNO_PERIPHERAL	1
#define PISM_BUSNO_TRACE	2

/*
 * PISM interfaces exposed to Bluespec; these must match similar definitions
 * in TopSimulation.bsv.
 */
#define	PISM_STRUCT_SIZE	512	/* Number of bits */
#define	PISM_PAD_BYTESIZE	(PISM_STRUCT_SIZE / 8)
#define	PISM_DATA_BYTES		32

struct pism_data_int {
	uint8_t		pdi_acctype;
	uint32_t	pdi_byteenable;
	uint8_t		pdi_data[PISM_DATA_BYTES];
	uint64_t	pdi_addr;
} __attribute__((__packed__));

struct pism_data {
	uint8_t			pad[PISM_PAD_BYTESIZE -
				    sizeof(struct pism_data_int)];
	struct pism_data_int	pd_int;
} __attribute__((__packed__));

typedef struct pism_data	pism_data_t;

#define	PISM_ACC_FETCH	0
#define	PISM_ACC_STORE	1

bool		pism_init(uint8_t busno);
void		pism_cycle_tick(uint8_t busno);
uint32_t	pism_interrupt_get(uint8_t busno);
bool		pism_request_ready(uint8_t busno, pism_data_t *req);
void		pism_request_put(uint8_t busno, pism_data_t *req);
bool		pism_response_ready(uint8_t busno);
pism_data_t	pism_response_get(uint8_t busno);
bool		pism_addr_valid(uint8_t busno, pism_data_t *req);

/*
 * Forward declare structs and typedefs so they can be used arbitrarily in
 * later structure definitions.
 */
struct pism_device;
struct pism_module;
typedef struct pism_device	pism_device_t;
typedef struct pism_module	pism_module_t;

struct pism_module	*pism_module_lookup(const char *);

typedef bool		pism_mod_init_t(pism_module_t *);

typedef bool		pism_dev_init_t(pism_device_t *);
typedef bool		pism_dev_interrupt_get_t(pism_device_t *);
typedef bool		pism_dev_request_ready_t(pism_device_t *,
			    pism_data_t *);
typedef void		pism_dev_request_put_t(pism_device_t *,
			    pism_data_t *);
typedef bool		pism_dev_response_ready_t(pism_device_t *);
typedef pism_data_t	pism_dev_response_get_t(pism_device_t *);
typedef bool		pism_dev_addr_valid_t(pism_device_t *, pism_data_t *);
typedef void		pism_dev_cycle_tick_t(pism_device_t *);

pism_data_t	pism_handler(pism_data_t	*arg);

/*
 * Simulator modules.
 */
struct pism_module {
	const char		*pm_name;
	const char		*pm_path;

	bool			pm_initialised;

	/*
	 * Pointer to array of valid option names.  The last entry should be
	 * NULL.
	 */
	const char		**pm_option_list;

	/*
	 * Module-private data handle.
	 */
	void			*pm_private;

	/*
	 * Methods on the module itself.
	 */
	pism_mod_init_t		*pm_mod_init;

	/*
	 * Methods on device instances.
	 */
	pism_dev_init_t			*pm_dev_init;
	pism_dev_interrupt_get_t	*pm_dev_interrupt_get;
	pism_dev_request_ready_t	*pm_dev_request_ready;
	pism_dev_request_put_t		*pm_dev_request_put;
	pism_dev_response_ready_t	*pm_dev_response_ready;
	pism_dev_response_get_t		*pm_dev_response_get;
	pism_dev_addr_valid_t		*pm_dev_addr_valid;
	pism_dev_cycle_tick_t		*pm_dev_cycle_tick;

	SLIST_ENTRY(pism_module) pm_next;
};
SLIST_HEAD(pism_modules, pism_module);
extern struct pism_modules *g_pism_modules;

#define	___mkstr(s...)	#s
#define	__mkstr(s...)	___mkstr(s)

#define	PISM_MODULE_INFO(tag)			\
	struct pism_module __pism_module_info	\
	__attribute__((used))			\
	__attribute__((section(".modinfo"),unused))

/*
 * Device abstractions
 */
struct pism_device_option {
	TAILQ_ENTRY(pism_device_option)	 pdo_entries;
	const char			*pdo_optname;
	const char			*pdo_optval;
};

struct pism_device {
	SLIST_ENTRY(pism_device) pd_next;
	struct pism_module	*pd_mod;
	const char		*pd_name;

	/*
	 * Device parameters configured by PISM and chericonf.
	 */
	uint32_t		pd_perms;	/* Permitted operations. */
	uint8_t			pd_busno;	/* Bus number. */
	uint64_t		pd_base;	/* Mapping base address. */
	uint64_t		pd_length;	/* Mapping length. */
	int			pd_irq;		/* IRQ, or -1 if none. */

	/*
	 * Text configuration file parameters captured, but not interpreted,
	 * by PISM.
	 */
	TAILQ_HEAD(, pism_device_option)	 pd_options;

	/*
	 * Module-private data for this device.
	 */
	void			*pd_private;
};
SLIST_HEAD(pism_devices, pism_device);
extern struct pism_devices *g_pism_devices[PISM_BUS_COUNT];

/*
 * Function calls relating to device configuration options.
 */
void	pism_device_option_add(pism_device_t *dev, const char *optname,
	    const char *optval);
bool	pism_device_option_get(pism_device_t *dev, const char *optname,
	    const char **optvalp);
bool	pism_device_option_parse_bool(pism_device_t *dev, const char *optval,
	    bool *boolp);
bool	pism_device_option_parse_longlong(pism_device_t *dev,
	    const char *optval, long long *llp);

bool	pism_device_options_finalise(pism_device_t *dev);

/*
 * Standard device options.
 */
#define	PISM_DEVICE_OPTION_ADDR		"addr"		/* Mapping address. */
#define	PISM_DEVICE_OPTION_LENGTH	"length"	/* Mapping length. */
#define	PISM_DEVICE_OPTION_PERMS	"perms"		/* Supported ops. */
#define	PISM_DEVICE_OPTION_IRQ		"irq"		/* Interrupt request. */

/*
 * Constants for the "perms" option.
 */
#define	PISM_PERM_ALLOW_FETCH_CHR	'f'	/* Allow fetch. */
#define	PISM_PERM_ALLOW_READ_CHR	'r'	/* Allow read (alias). */
#define	PISM_PERM_ALLOW_STORE_CHR	's'	/* Allow store. */
#define	PISM_PERM_ALLOW_WRITE_CHR	'w'	/* Allow write (alias). */
#define PISM_PERM_ALLOW_CREATE_CHR	'c'	/* Allow file creation for mmap. */

#define	PISM_PERM_ALLOW_DEFAULT_STR	"fs"	/* Default. */

#define	PISM_PERM_ALLOW_FETCH		0x00000001	/* Allow fetch. */
#define	PISM_PERM_ALLOW_STORE		0x00000002	/* Allow store. */
#define PISM_PERM_ALLOW_CREATE		0x00000004

/*
 * Constants for the "irq" option.  Once we support programmable interrupt
 * controllers, something more mature will be required here.
 */
#define	PISM_IRQ_NONE			(-1)
#define	PISM_IRQ_MIN			0	/* Minimum IRQ number. */
#define	PISM_IRQ_MAX			4	/* Maximum IRQ number. */

/*
 * Utility functions provided by PISM for device implementations.
 */
uint64_t	pism_cycle_count_get(uint8_t busno);

/*
 * Macros operating on PISM requests.
 */
#define	PISM_DEV_REQ_ADDR(dev, req)					\
	((req)->pd_int.pdi_addr - (dev)->pd_base)

#define	PISM_REQ_ACCTYPE(req)						\
	((req)->pd_int.pdi_acctype)

#define	PISM_REQ_BYTEENABLED(req, i)					\
	((req)->pd_int.pdi_byteenable & (1 << (i)))

#define	PISM_REQ_BYTE(req, i)						\
	((req)->pd_int.pdi_data[(i)])

#endif /* _PISM_H_ */
