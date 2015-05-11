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

#define _BSD_SOURCE
#define _XOPEN_SOURCE 500

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/queue.h>
#include <sys/stat.h>

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

/*-
 * PISM simulation of the Altera SD Card University Program IP Core, which
 * provides a simplified, programmed I/O interface to an SD Card.  Currently,
 * SD Card contents can be filled from a backing file image on local disk.
 * Only a (very) small number of SD Card functions are implemented.
 */

static pism_mod_init_t			sdcard_mod_init;
static pism_dev_request_ready_t		sdcard_dev_request_ready;
static pism_dev_request_put_t		sdcard_dev_request_put;
static pism_dev_response_ready_t	sdcard_dev_response_ready;
static pism_dev_response_get_t		sdcard_dev_response_get;
static pism_dev_addr_valid_t		sdcard_dev_addr_valid;

/*
 * I/O register/buffer offsets, from Table 4.1.1 in the Altera University
 * Program SD Card IP Core specification.  We implement only a small subset of
 * the fields required to support the FreeBSD driver -- for example, no SR or
 * CID registers.
 */
#define	ALTERA_SDCARD_OFF_RXTX_BUFFER	0	/* 512-byte I/O buffer */
#define	ALTERA_SDCARD_OFF_CSD		528	/* 16-byte Card Specific Data */
#define	ALTERA_SDCARD_OFF_CMD_ARG	556	/* Command Argument Register */
#define	ALTERA_SDCARD_OFF_CMD		560	/* Command Register */
#define	ALTERA_SDCARD_OFF_ASR		564	/* Auxiliary Status Register */
#define	ALTERA_SDCARD_OFF_RR1		568	/* Response R1 */

/*
 * Sizes and constructed offsets.
 */
#define	ALTERA_SDCARD_CSD_SIZE	16
#define	ALTERA_SDCARD_RXTX_BUFFER_SIZE	ALTERA_SDCARD_OFF_CID
#define	ALTERA_SDCARD_OFF_REG_BASE	ALTERA_SDCARD_OFF_CID
#define	ALTERA_SDCARD_OFF_REG_SIZE	(ALTERA_SDCARD_OFF_RR1 + 2)
#define	SDCARD_DATA_SIZE	1024

/*
 * The Altera IP Core provides a 16-bit "Additional Status Register" (ASR)
 * beyond those described in the SD Card specification that captures IP Core
 * transaction state, such as whether the last command is in progress, the
 * card has been removed, etc.
 */
#define	ALTERA_SDCARD_ASR_CMDVALID	0x0001
#define	ALTERA_SDCARD_ASR_CARDPRESENT	0x0002
#define	ALTERA_SDCARD_ASR_CMDINPROGRESS	0x0004
#define	ALTERA_SDCARD_ASR_SRVALID	0x0008
#define	ALTERA_SDCARD_ASR_CMDTIMEOUT	0x0010
#define	ALTERA_SDCARD_ASR_CMDDATAERROR	0x0020

/*
 * Constants for interpreting the SD Card Card Specific Data (CSD) register.
 */
#define	ALTERA_SDCARD_CSD_STRUCTURE_BYTE	15
#define	ALTERA_SDCARD_CSD_STRUCTURE_MASK	0xc0	/* 2 bits */
#define	ALTERA_SDCARD_CSD_STRUCTURE_LSHIFT	6

#define	ALTERA_SDCARD_CSD_READ_BL_LEN_BYTE	10
#define	ALTERA_SDCARD_CSD_READ_BL_LEN_MASK	0x0f	/* 4 bits */

/*
 * C_SIZE is a 12-bit field helpfully split over three different bytes of CSD
 * data.  Software ease of use was not a design consideration.
 */
#define	ALTERA_SDCARD_CSD_C_SIZE_BYTE0		7
#define	ALTERA_SDCARD_CSD_C_SIZE_MASK0		0x3	/* bottom 2 bits */
#define	ALTERA_SDCARD_CSD_C_SIZE_LSHIFT0	6

#define	ALTERA_SDCARD_CSD_C_SIZE_BYTE1		8
#define	ALTERA_SDCARD_CSD_C_SIZE_MASK1		0x3fc	/* middle 8 bits */
#define	ALTERA_SDCARD_CSD_C_SIZE_RSHIFT1	2

#define	ALTERA_SDCARD_CSD_C_SIZE_BYTE2		9
#define	ALTERA_SDCARD_CSD_C_SIZE_MASK2		0xc00	/* top 2 bits */
#define	ALTERA_SDCARD_CSD_C_SIZE_RSHIFT2	10

#define	ALTERA_SDCARD_CSD_C_SIZE_MULT_BYTE0	5
#define	ALTERA_SDCARD_CSD_C_SIZE_MULT_MASK0	0x1	/* bottom 1 bit */
#define	ALTERA_SDCARD_CSD_C_SIZE_MULT_LSHIFT0	7

#define	ALTERA_SDCARD_CSD_C_SIZE_MULT_BYTE1	6
#define	ALTERA_SDCARD_CSD_C_SIZE_MULT_MASK1	0x6	/* top 2 bits */
#define	ALTERA_SDCARD_CSD_C_SIZE_MULT_RSHIFT1	1


/*
 * The Altera IP Core provides a 16-bit "Response R1" regster (RR1) beyond
 * those described in the SD Card specification that holds additional
 * information on the most recently completed command sent to the unit.
 *
 * XXXRW: The SD Card IP Core documentation is observably erroneous about how
 * it documents these bits, and misleading about how well they work.  We do
 * our best in trying to be compatible with the FreeBSD altera_sdcard device
 * driver, which is known to work with the actual hardware.
 */
#define	ALTERA_SDCARD_RR1_INITPROCRUNNING	0x0100
#define	ALTERA_SDCARD_RR1_ERASEINTERRUPTED	0x0200
#define	ALTERA_SDCARD_RR1_ILLEGALCOMMAND	0x0400
#define	ALTERA_SDCARD_RR1_COMMANDCRCFAILED	0x0800
#define	ALTERA_SDCARD_RR1_ADDRESSMISALIGNED	0x1000
#define	ALTERA_SDCARD_RR1_ADDRBLOCKRANGE	0x2000

/*
 * Although SD Cards may have various sector sizes, the Altera IP Core
 * requires that I/O be done in 512-byte chunks.  It also supports only up to
 * 2GB cards.  We select a C_SIZE_MULT such that image files must be an even
 * multiple of 256K.
 */
#define	ALTERA_SDCARD_SECTORSIZE	512
#define	ALTERA_SDCARD_MAXSIZE		(2ULL * 1024 * 1024 * 1024)
#define	ALTERA_SDCARD_CSIZEUNIT		(512 * 1024)

/*
 * SD Card commands used in this driver.
 */
#define	ALTERA_SDCARD_CMD_SEND_RCA	0x03	/* Retrieve card RCA. */
#define	ALTERA_SDCARD_CMD_SEND_CSD	0x09	/* Retrieve CSD register. */
#define	ALTERA_SDCARD_CMD_SEND_CID	0x0A	/* Retrieve CID register. */
#define	ALTERA_SDCARD_CMD_READ_BLOCK	0x11	/* Read block from disk. */
#define	ALTERA_SDCARD_CMD_WRITE_BLOCK	0x18	/* Write block to disk. */

/*
 * Data structure describing per-SDCARD instance fields, hung off of
 * pism_device_t->pd_private.  Once we support pipelining, sdp_reqfifo will
 * need to actually be a FIFO, and the reply cycle will be per-entry.
 */
struct sdcard_private {
	int		 sdp_imagefile;		/* Image file. */
	uint64_t	 sdp_length;		/* Image file length. */
	pism_data_t	 sdp_reqfifo;
	bool		 sdp_reqfifo_empty;
	bool		 sdp_readonly;
	unsigned int	 sdp_delay;
	uint64_t	 sdp_replycycle;  /* Earliest cycle reply permitted. */

	/*
	 * The SD Card simulation configures and exports two regions of memory
	 * -- one containing various IP Core and SD Card control registers,
	 * and the other an I/O buffer.  Both are represented within the
	 * driver by actual memory in order to simplify memory operations.  We
	 * always access this as a little-endian, byte-oriented array.
	 */
	uint8_t		 sdp_data[SDCARD_DATA_SIZE];
};

/*
 * SDCARD-specific option names.
 */
#define	SDCARD_OPTION_PATH	"path"	/* File system path to memory map. */
#define	SDCARD_OPTION_DELAY	"delay"	/* Cycles each read takes. */
#define	SDCARD_OPTION_READONLY	"readonly"	/* Read-only. */

#define	SDCARD_DELAY_DEFAULT	1
#define	SDCARD_DELAY_MINIMUM	1
#define	SDCARD_DELAY_MAXIMUM	UINT_MAX

static char		*g_sdcard_debug = NULL;

#define	DDBG(...)	do	{		\
	if (g_sdcard_debug == NULL) {		\
		break;				\
	}					\
	printf("%s(%d): ", __func__, __LINE__);	\
	printf(__VA_ARGS__);			\
	printf("\n");				\
} while (0)

#define	ROUNDUP(x, y)	((((x) + (y) - 1)/(y)) * (y))

static void
sdcard_csd_set(struct sdcard_private *sdpp, uint8_t csd_structure,
    uint8_t read_bl_len, uint16_t c_size, uint8_t c_size_mult)
{

	sdpp->sdp_data[ALTERA_SDCARD_OFF_CSD +
	    ALTERA_SDCARD_CSD_STRUCTURE_BYTE] |=
	    (csd_structure << ALTERA_SDCARD_CSD_STRUCTURE_LSHIFT);

	sdpp->sdp_data[ALTERA_SDCARD_OFF_CSD +
	    ALTERA_SDCARD_CSD_READ_BL_LEN_BYTE] |= read_bl_len;

	sdpp->sdp_data[ALTERA_SDCARD_OFF_CSD +
	    ALTERA_SDCARD_CSD_C_SIZE_MULT_BYTE0] |=
	    ((c_size_mult & ALTERA_SDCARD_CSD_C_SIZE_MULT_MASK0) <<
	    ALTERA_SDCARD_CSD_C_SIZE_MULT_LSHIFT0);
	sdpp->sdp_data[ALTERA_SDCARD_OFF_CSD +
	    ALTERA_SDCARD_CSD_C_SIZE_MULT_BYTE1] |=
	    ((c_size_mult & ALTERA_SDCARD_CSD_C_SIZE_MULT_MASK1) >>
	    ALTERA_SDCARD_CSD_C_SIZE_MULT_RSHIFT1);

	sdpp->sdp_data[ALTERA_SDCARD_OFF_CSD +
	    ALTERA_SDCARD_CSD_C_SIZE_BYTE0] |=
	    ((c_size & ALTERA_SDCARD_CSD_C_SIZE_MASK0) <<
	    ALTERA_SDCARD_CSD_C_SIZE_LSHIFT0);
	sdpp->sdp_data[ALTERA_SDCARD_OFF_CSD +
	    ALTERA_SDCARD_CSD_C_SIZE_BYTE1] |=
	    ((c_size & ALTERA_SDCARD_CSD_C_SIZE_MASK1) >>
	    ALTERA_SDCARD_CSD_C_SIZE_RSHIFT1);
	sdpp->sdp_data[ALTERA_SDCARD_OFF_CSD +
	    ALTERA_SDCARD_CSD_C_SIZE_BYTE2] |=
	    ((c_size & ALTERA_SDCARD_CSD_C_SIZE_MASK2) >>
	    ALTERA_SDCARD_CSD_C_SIZE_RSHIFT2);
}

static void
sdcard_asr_get(struct sdcard_private *sdpp, uint16_t *asrp)
{

	*asrp = le16toh(*(uint16_t *)&sdpp->sdp_data[ALTERA_SDCARD_OFF_ASR]);
}

static void
sdcard_asr_set(struct sdcard_private *sdpp, uint16_t asr)
{

	*(uint16_t *)&sdpp->sdp_data[ALTERA_SDCARD_OFF_ASR] = htole16(asr);
}

static void
sdcard_asr_clearbits(struct sdcard_private *sdpp, uint16_t bits)
{
	uint16_t asr;

	sdcard_asr_get(sdpp, &asr);
	asr &= ~bits;
	sdcard_asr_set(sdpp, asr);
}

static void
sdcard_asr_setbits(struct sdcard_private *sdpp, uint16_t bits)
{
	uint16_t asr;

	sdcard_asr_get(sdpp, &asr);
	asr |= bits;
	sdcard_asr_set(sdpp, asr);
}

static void
sdcard_rr1_set(struct sdcard_private *sdpp, uint16_t rr1)
{

	*(uint16_t *)&sdpp->sdp_data[ALTERA_SDCARD_OFF_RR1] = htole16(rr1);
}

static void
sdcard_cmd_get(struct sdcard_private *sdpp, uint16_t *cmdp)
{

	*cmdp = le16toh(*(uint16_t *)&sdpp->sdp_data[ALTERA_SDCARD_OFF_CMD]);
}

static void
sdcard_cmd_arg_get(struct sdcard_private *sdpp, uint32_t *cmd_argp)
{

	*cmd_argp =
	    le32toh(*(uint32_t *)&sdpp->sdp_data[ALTERA_SDCARD_OFF_CMD_ARG]);
}

static bool
sdcard_mod_init(pism_module_t *mod)
{

	DDBG("called");

	g_sdcard_debug = getenv("CHERI_DEBUG_SDCARD");

	DDBG("returned");
	return (true);
}

static bool
sdcard_dev_init(pism_device_t *dev)
{
	struct stat sb;
	struct sdcard_private *sdpp;
	const char *option_path, *option_delay, *option_readonly;
	uint64_t length;
	uint16_t c_size;
	uint8_t csd_structure, c_size_mult, read_bl_len;
	long long delayll;
	int delay, fd, open_flags;
	bool readonly;

	DDBG("called for mapping at %jx, length %jx", dev->pd_base,
	    dev->pd_length);

	assert(dev->pd_base % PISM_DATA_BYTES == 0);
	assert(dev->pd_length % PISM_DATA_BYTES == 0);
	assert(dev->pd_length == SDCARD_DATA_SIZE);

	/*
	 * Query and validate options before doing any allocation.
	 */
	if (!(pism_device_option_get(dev, SDCARD_OPTION_PATH, &option_path)))
		option_path = NULL;
	if (!(pism_device_option_get(dev, SDCARD_OPTION_DELAY, &option_delay)))
		option_delay = NULL;
	if (!(pism_device_option_get(dev, SDCARD_OPTION_READONLY,
	    &option_readonly)))
		option_readonly = NULL;
	if (option_path == NULL) {
		warnx("%s: option path required on device %s", __func__,
		    dev->pd_name);
		return (false);
	}
	if (option_delay != NULL) {
		if (!pism_device_option_parse_longlong(dev, option_delay,
		    &delayll)) {
			warnx("%s: invalid delay option on device %s",
			    __func__, dev->pd_name);
			return (false);
		}
		if (delayll < SDCARD_DELAY_MINIMUM) {
			warnx("%s: requested delay %lld below minimum %d on "
			    "device %s", __func__, delayll,
			    SDCARD_DELAY_MINIMUM, dev->pd_name);
			return (false);
		}
		if (delayll > SDCARD_DELAY_MAXIMUM) {
			warnx("%s: requested delay %lld above maximum %d on "
			    "device %s", __func__, delayll,
			    SDCARD_DELAY_MAXIMUM, dev->pd_name);
			return (false);
		}
		delay = delayll;
	} else
		delay = SDCARD_DELAY_DEFAULT;
	if (option_readonly != NULL) {
		if (!pism_device_option_parse_bool(dev, option_readonly,
		    &readonly)) {
			warnx("%s: invalid readonly option on device %s",
			    __func__, dev->pd_name);
			return (false);
		}
	} else
		readonly = false;

	/*
	 * Although we might restrict SD Card access to read-only, the SD Card
	 * IP core relies on stores even when reading, so require both fetch
	 * and store rights.  Instead we rely on the "readonly" PISM device
	 * option.
	 */
	assert(dev->pd_perms &
	    (PISM_PERM_ALLOW_FETCH | PISM_PERM_ALLOW_STORE));
	if (readonly)
		open_flags = O_RDONLY;
	else
		open_flags = O_RDWR;
	fd = open(option_path, open_flags);
	if (fd < 0) {
		warn("%s: open of %s failed on device %s", __func__,
		    option_path, dev->pd_name);
		return (false);
	}

	/*
	 * We can't handle live resize on SD Card images, and support only
	 * even multiples of 512 byte sector-size.
	 */
	if (fstat(fd, &sb) < 0) {
		warn("%s: fstat of %s failed on device %s", __func__,
		    option_path, dev->pd_name);
		close(fd);
		return (false);
	}
	length = sb.st_size;
	if (length > ALTERA_SDCARD_MAXSIZE) {
		warnx("%s: truncating image from %ju to maximum SD Card size "
		    "%ju", __func__, length,
		    (uintmax_t)ALTERA_SDCARD_MAXSIZE);
		length = ALTERA_SDCARD_MAXSIZE;
	}
	if (length % ALTERA_SDCARD_SECTORSIZE != 0) {
		warnx("%s: rounding image size up from %ju to %ju on device "
		    "%s", __func__, (uintmax_t)sb.st_size,
		    (uintmax_t)length, dev->pd_name);
		length = ROUNDUP(length, ALTERA_SDCARD_SECTORSIZE);
	}
	if (length % ALTERA_SDCARD_CSIZEUNIT != 0) {
		warnx("%s: rounding up image size from %ju to nearest "
		    "multiple of %ju", __func__, length,
		    (uintmax_t)ALTERA_SDCARD_CSIZEUNIT);
		length = ROUNDUP(length, ALTERA_SDCARD_CSIZEUNIT);
	}
	sdpp = calloc(1, sizeof(*sdpp));
	if (sdpp == NULL) {
		warn("%s: calloc", __func__);
		close(fd);
		return (false);
	}
	sdpp->sdp_imagefile = fd;
	sdpp->sdp_delay = delay;
	sdpp->sdp_reqfifo_empty = true;
	dev->pd_private = sdpp;
	sdpp->sdp_length = length;

	/*
	 * Initialise IP Core registers.  All memory is initialially zero'd
	 * above, so only set fields that require non-zero values.
	 */

	/*
	 * Additional Status Register (ASR).  Card is always present.
	 */
	sdcard_asr_set(sdpp, ALTERA_SDCARD_ASR_CARDPRESENT);

	/*-
	 * Initialise SD Card registers.  Card capacity for an SD Card is
	 * expressed using three CSD fields -- c_size, read_bl_len, and
	 * c_size_mult, which are combined as follows:
	 *
	 *   Memory capacity = BLOCKNR * BLOCK_LEN
	 *
	 * Where:
	 *
	 *   BLOCKNR = (C_SIZE + 1) * MULT
	 *   MULT = 2^(C_SIZE_MULT+2)
	 *   BLOCK_LEN = 2^READ_BL_LEN
	 */
	csd_structure = 0;
	c_size = (length / ALTERA_SDCARD_CSIZEUNIT) - 1;
	read_bl_len = 10;			/* 512 byte blocks. */
	c_size_mult = 7;			/* Up to 2G disk sizes. */
	sdcard_csd_set(sdpp, csd_structure, read_bl_len, c_size, c_size_mult);

	DDBG("returned");
	return (true);
}

/*
 * Implement BLOCK_READ and BLOCK_WRITE.
 *
 * XXXRW: As these are instaneous, ALTERA_SDCARD_ASR_CMDINPROGRESS is not
 * actually used.  It would be nice to implement a more complete state machine
 * with configurable read and write delays.
 */
static void
sdcard_cmd_read(struct sdcard_private *sdpp)
{
	uint32_t cmd_arg;
	ssize_t len;

	/*
	 * XXXRW: It's not clear if ALTERA_SDCARD_ASR_CMDDATAERROR should be
	 * set.
	 */
	sdcard_cmd_arg_get(sdpp, &cmd_arg);
	if (cmd_arg % ALTERA_SDCARD_SECTORSIZE != 0) {
		sdcard_asr_clearbits(sdpp, ALTERA_SDCARD_ASR_CMDVALID);
		sdcard_asr_setbits(sdpp, ALTERA_SDCARD_ASR_CMDDATAERROR);
		sdcard_rr1_set(sdpp, ALTERA_SDCARD_RR1_ADDRESSMISALIGNED);
		return;
	}
	if (cmd_arg + ALTERA_SDCARD_SECTORSIZE > sdpp->sdp_length) {
		sdcard_asr_clearbits(sdpp, ALTERA_SDCARD_ASR_CMDVALID);
		sdcard_asr_setbits(sdpp, ALTERA_SDCARD_ASR_CMDDATAERROR);
		sdcard_rr1_set(sdpp, ALTERA_SDCARD_RR1_ADDRBLOCKRANGE);
		return;
	}
	len = pread(sdpp->sdp_imagefile,
	    &sdpp->sdp_data[ALTERA_SDCARD_OFF_RXTX_BUFFER],
	    ALTERA_SDCARD_SECTORSIZE, cmd_arg);
	if (len != ALTERA_SDCARD_SECTORSIZE) {
		sdcard_asr_setbits(sdpp, ALTERA_SDCARD_ASR_CMDDATAERROR);
		return;
	}
	sdcard_asr_clearbits(sdpp, ALTERA_SDCARD_ASR_CMDDATAERROR);
	sdcard_asr_setbits(sdpp, ALTERA_SDCARD_ASR_CMDVALID);
	sdcard_rr1_set(sdpp, 0);	/* Three cheers! */
}

static void
sdcard_cmd_write(struct sdcard_private *sdpp)
{
	uint32_t cmd_arg;
	ssize_t len;

	/*
	 * XXXRW: It's not clear if ALTERA_SDCARD_ASR_CMDDATAERROR should be
	 * set.
	 */
	sdcard_cmd_arg_get(sdpp, &cmd_arg);
	if (cmd_arg % ALTERA_SDCARD_SECTORSIZE != 0) {
		sdcard_asr_clearbits(sdpp, ALTERA_SDCARD_ASR_CMDVALID);
		sdcard_asr_setbits(sdpp, ALTERA_SDCARD_ASR_CMDDATAERROR);
		sdcard_rr1_set(sdpp, ALTERA_SDCARD_RR1_ADDRESSMISALIGNED);
		return;
	}
	if (cmd_arg + ALTERA_SDCARD_SECTORSIZE > sdpp->sdp_length) {
		sdcard_asr_clearbits(sdpp, ALTERA_SDCARD_ASR_CMDVALID);
		sdcard_asr_setbits(sdpp, ALTERA_SDCARD_ASR_CMDDATAERROR);
		sdcard_rr1_set(sdpp, ALTERA_SDCARD_RR1_ADDRBLOCKRANGE);
		return;
	}

	/*
	 * XXXRW: The documentation doesn't explain how read-only cards are
	 * reported.  Go for an illegal command for now, but in the future we
	 * will want to compare with actual hardware behaviour.
	 */
	if (sdpp->sdp_readonly) {
		sdcard_asr_clearbits(sdpp, ALTERA_SDCARD_ASR_CMDVALID);
		sdcard_rr1_set(sdpp, ALTERA_SDCARD_RR1_ILLEGALCOMMAND);
		return;
	}
	len = pwrite(sdpp->sdp_imagefile,
	    &sdpp->sdp_data[ALTERA_SDCARD_OFF_RXTX_BUFFER],
	    ALTERA_SDCARD_SECTORSIZE, cmd_arg);
	if (len != ALTERA_SDCARD_SECTORSIZE) {
		sdcard_asr_setbits(sdpp, ALTERA_SDCARD_ASR_CMDDATAERROR);
		return;
	}
	sdcard_asr_setbits(sdpp, ALTERA_SDCARD_ASR_CMDVALID |
	    ALTERA_SDCARD_ASR_CMDDATAERROR);	/* Surprising but true. */
	sdcard_rr1_set(sdpp, 0);		/* Three cheers! */
}

/*
 * Check whether the CMD register was written.  If so, handle the results.
 */
static void
sdcard_cmd_handle(struct sdcard_private *sdpp, pism_data_t *req,
    uint64_t addr)
{
	int i;
	bool was_cmd;
	uint16_t cmd;

	/*
 	 * Check for a write to the first byte of each word -- real hardware
 	 * has strong alignment requirements here as well, and will likewise
 	 * misbehave if anything but a properly sized and aligned write
 	 * occurs.
 	 */
	was_cmd = false;
	for (i = 0; i < PISM_DATA_BYTES; i++) {
		if (!PISM_REQ_BYTEENABLED(req, i))
			continue;
		if (addr + i == ALTERA_SDCARD_OFF_CMD)
			was_cmd = true;
	}
	if (!was_cmd)
		return;
	sdcard_cmd_get(sdpp, &cmd);
	switch (cmd) {
	case ALTERA_SDCARD_CMD_READ_BLOCK:
		sdcard_cmd_read(sdpp);
		break;

	case ALTERA_SDCARD_CMD_WRITE_BLOCK:
		sdcard_cmd_write(sdpp);
		break;

	default:
		warnx("%s: invalid command %04x", __func__, cmd);
		sdcard_asr_clearbits(sdpp, ALTERA_SDCARD_ASR_CMDVALID);
		sdcard_rr1_set(sdpp, ALTERA_SDCARD_RR1_ILLEGALCOMMAND);
		break;
	}
}

static bool
sdcard_dev_request_ready(pism_device_t *dev, pism_data_t *req)
{
	struct sdcard_private *sdpp;

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

static void
sdcard_dev_request_put(pism_device_t *dev, pism_data_t *req)
{
	struct sdcard_private *sdpp;
	uint64_t addr;
	int i;

	DDBG("called");

	sdpp = dev->pd_private;
	assert(sdpp != NULL);

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		addr = PISM_DEV_REQ_ADDR(dev, req);
		for (i = 0; i < PISM_DATA_BYTES; i++) {
			if (!PISM_REQ_BYTEENABLED(req, i))
				continue;
			assert(addr + i < sdpp->sdp_length);
			sdpp->sdp_data[addr + i] = PISM_REQ_BYTE(req, i);

		}
		sdcard_cmd_handle(sdpp, req, addr);
		break;

	case PISM_ACC_FETCH:
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
sdcard_dev_response_ready(pism_device_t *dev)
{
	struct sdcard_private *sdpp;
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

	DDBG("returned - %d", ret);
	return (ret);
}

static pism_data_t
sdcard_dev_response_get(pism_device_t *dev)
{
	struct sdcard_private *sdpp;
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
		for (i = 0; i < PISM_DATA_BYTES; i++) {
			assert(addr + i >= 0 && addr + i <
			    sizeof(sdpp->sdp_data));
			if (PISM_REQ_BYTEENABLED(req, i)) {
				PISM_REQ_BYTE(req, i) =
				    sdpp->sdp_data[addr + i];
			} else
				PISM_REQ_BYTE(req, i) = 0xab;	/* Filler. */
		}
		break;

	default:
		assert(0);
	}
	return (*req);
}

static bool
sdcard_dev_addr_valid(pism_device_t *dev, pism_data_t *req)
{

	return (true);
}

static const char *sdcard_option_list[] = {
	SDCARD_OPTION_PATH,
	SDCARD_OPTION_DELAY,
	SDCARD_OPTION_READONLY,
	NULL
};

PISM_MODULE_INFO(sdcard_module) = {
	.pm_name = "sdcard",
	.pm_option_list = sdcard_option_list,
	.pm_mod_init = sdcard_mod_init,
	.pm_dev_init = sdcard_dev_init,
	.pm_dev_request_ready = sdcard_dev_request_ready,
	.pm_dev_request_put = sdcard_dev_request_put,
	.pm_dev_response_ready = sdcard_dev_response_ready,
	.pm_dev_response_get = sdcard_dev_response_get,
	.pm_dev_addr_valid = sdcard_dev_addr_valid,
};
