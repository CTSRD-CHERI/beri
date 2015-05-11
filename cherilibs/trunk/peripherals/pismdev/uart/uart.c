/*-
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2011-2012 Jonathan Woodruff
 * Copyright (c) 2012 Philip Paeps
 * Copyright (c) 2011-2012 Robert N. M. Watson
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
#include <sys/types.h>
#include <sys/mman.h>
#include <sys/queue.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>

#include <assert.h>
#include <err.h>
#if defined(__linux__)
#include <endian.h>
#elif (__FreeBSD__)
#include <sys/endian.h>
#endif
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <stdbool.h>
#include <unistd.h>

#include "pismdev/pism.h"
#include "include/parameters.h"

static pism_mod_init_t			uart_mod_init;
static pism_dev_init_t			uart_dev_init;
static pism_dev_interrupt_get_t		uart_dev_interrupt_get;
static pism_dev_request_ready_t		uart_dev_request_ready;
static pism_dev_request_put_t		uart_dev_request_put;
static pism_dev_response_ready_t	uart_dev_response_ready;
static pism_dev_response_get_t		uart_dev_response_get;
static pism_dev_addr_valid_t		uart_dev_addr_valid;

struct uart_private {
	struct pism_device	*up_dev;	/* Associated PISM device. */
	int		up_type;		/* UART type. */
	int		up_listensock;		/* Listen socket, if any. */
	int		up_fdinput;		/* Input file descriptor. */
	int		up_fdoutput;		/* Output file descriptor. */
	uint32_t	up_control;		/* Control register. */
	pism_data_t	up_reqfifo;		/* 1-element FIFO. */
	bool		up_reqfifo_empty;
};

static char *g_uart_debug = NULL;
#define	UDBG(upp, ...)	do {						\
	if (g_uart_debug == NULL) {					\
		break;							\
	}								\
	if (upp != NULL)						\
		printf("%s(%d): %s ", __func__, __LINE__,		\
		    upp->up_dev->pd_name);				\
	else								\
		printf("%s(%d): ", __func__, __LINE__);			\
	printf(__VA_ARGS__);						\
	printf("\n");							\
} while (0)

/*
 * UART-specific option names.
 */
#define	UART_OPTION_TYPE		"type"
#define	UART_OPTION_PATH		"path"
#define	UART_OPTION_APPEND		"append"

/*
 * Possible strings for the "type" option.
 */
#define	UART_TYPE_STDIO_STR		"stdio"
#define	UART_TYPE_FILE_STR		"file"
#define	UART_TYPE_SOCKET_STR		"socket"
#define	UART_TYPE_NULL_STR		"null"

/*
 * Options in internalised form.
 */
#define	UART_TYPE_STDIO			0
#define	UART_TYPE_FILE			1
#define	UART_TYPE_SOCKET		2
#define	UART_TYPE_NULL			3
#define	UART_TYPE_DEFAULT		UART_TYPE_STDIO

/*-
 * Routines for interacting with the CHERI console UART.  Programming details
 * from the June 2011 "Embedded Peripherals User Guide" by Altera
 * Corporation, tables 6-2 (JTAG UART Core Register Map), 6-3 (Data Register
 * Bits), and 6-4 (Control Register Bits).
 *
 * Offsets of data and control registers relative to the base.  Altera
 * conventions are maintained in CHERI.
 */
#define	ALTERA_JTAG_UART_DATA_OFF	0x00000000
#define	ALTERA_JTAG_UART_CONTROL_OFF	0x00000004

/*
 * Offset 0: 'data' register -- bits 31-16 (RAVAIL), 15 (RVALID),
 * 14-8 (Reserved), 7-0 (DATA).
 *
 * DATA - One byte read or written.
 * RAVAIL - Bytes available to read (excluding the current byte).
 * RVALID - Whether the byte in DATA is valid.
 */
#define	ALTERA_JTAG_UART_DATA_DATA		0x000000ff
#define	ALTERA_JTAG_UART_DATA_RESERVED		0x00007f00
#define	ALTERA_JTAG_UART_DATA_RVALID		0x00008000
#define	ALTERA_JTAG_UART_DATA_RAVAIL		0xffff0000
#define	ALTERA_JTAG_UART_DATA_RAVAIL_SHIFT	16

/*-
 * Offset 1: 'control' register -- bits 31-16 (WSPACE), 15-11 (Reserved),
 * 10 (AC), 9 (WI), 8 (RI), 7..2 (Reserved), 1 (WE), 0 (RE).
 *
 * RE - Enable read interrupts.
 * WE - Enable write interrupts.
 * RI - Read interrupt pending.
 * WI - Write interrupt pending.
 * AC - Activity bit; set to '1' to clear to '0'.
 * WSPACE - Space available in the write FIFO.
 */
#define	ALTERA_JTAG_UART_CONTROL_RE		0x00000001
#define	ALTERA_JTAG_UART_CONTROL_WE		0x00000002
#define	ALTERA_JTAG_UART_CONTROL_RESERVED0	0x000000fc
#define	ALTERA_JTAG_UART_CONTROL_RI		0x00000100
#define	ALTERA_JTAG_UART_CONTROL_WI		0x00000200
#define	ALTERA_JTAG_UART_CONTROL_AC		0x00000400
#define	ALTERA_JTAG_UART_CONTROL_RESERVED1	0x0000f800
#define	ALTERA_JTAG_UART_CONTROL_WSPACE		0xffff0000
#define	ALTERA_JTAG_UART_CONTROL_WSPACE_SHIFT	16

#define	ALTERA_JTAG_UART_CONTROL_PERSISTENT				\
	(ALTERA_JTAG_UART_CONTROL_RE | ALTERA_JTAG_UART_CONTROL_WE |	\
	    ALTERA_JTAG_UART_CONTROL_AC)

static bool
uart_mod_init(pism_module_t *mod)
{

	g_uart_debug = getenv("CHERI_DEBUG_UART");
	return (true);
}

static bool
uart_str_to_type(const char *str, int *typep)
{

	if (strcmp(str, UART_TYPE_STDIO_STR) == 0) {
		*typep = UART_TYPE_STDIO;
		return (true);
	} else if (strcmp(str, UART_TYPE_FILE_STR) == 0) {
		*typep = UART_TYPE_FILE;
		return (true);
	} else if (strcmp(str, UART_TYPE_SOCKET_STR) == 0) {
		*typep = UART_TYPE_SOCKET;
		return (true);
	} else if (strcmp(str, UART_TYPE_NULL_STR) == 0) {
		*typep = UART_TYPE_NULL;
		return (true);
	}
	return (false);
}

static bool
uart_dev_init(pism_device_t *dev)
{
	struct uart_private *upp;
	struct sockaddr_un sun;
	const char *option_type, *option_path, *option_append;
	int fd, open_flags, uart_type;
	bool append_flag, ret;

	assert(dev->pd_base % PISM_DATA_BYTES == 0);
	assert(dev->pd_length == PISM_DATA_BYTES);

	/*
	 * Query and validate options before doing any allocation.
	 */
	ret = true;
	if (!(pism_device_option_get(dev, UART_OPTION_TYPE, &option_type)))
		option_type = NULL;
	if (!(pism_device_option_get(dev, UART_OPTION_PATH, &option_path)))
		option_path = NULL;
	if (!(pism_device_option_get(dev, UART_OPTION_APPEND,
	    &option_append)))
		option_append = NULL;
	if (option_type != NULL) {
		if (!(uart_str_to_type(option_type, &uart_type))) {
			warnx("%s: invalid UART type on device %s", __func__,
			    dev->pd_name);
			ret = false;
			goto out;
		}
	} else
		uart_type = UART_TYPE_DEFAULT;
	if ((uart_type == UART_TYPE_FILE || uart_type == UART_TYPE_SOCKET) &&
	    option_path == NULL) {
		warnx("%s: UART type file or type socket requires path on "
		    "device %s", __func__, dev->pd_name);
		ret = false;
		goto out;
	} else if ((uart_type != UART_TYPE_FILE &&
	    uart_type != UART_TYPE_SOCKET) && option_path != NULL) {
		warnx("%s: unexpected path option on device %s", __func__,
		    dev->pd_name);
		ret = false;
		goto out;
	}
	if (option_append != NULL) {
		if (uart_type != UART_TYPE_FILE) {
			warnx("%s: unexpected append option on device %s",
			    __func__, dev->pd_name);
			ret = false;
			goto out;
		}
		if (!(pism_device_option_parse_bool(dev, option_append,
		    &append_flag))) {
			warnx("%s: invalid append option on device %s",
			    __func__, dev->pd_name);
			ret = false;
			goto out;
		}
	} else
		append_flag = false;

	upp = calloc(1, sizeof(*upp));
	assert(upp != NULL);
	upp->up_dev = dev;
	upp->up_type = uart_type;
	switch (uart_type) {
	case UART_TYPE_STDIO:
		upp->up_fdinput = STDIN_FILENO;
		upp->up_fdoutput = STDOUT_FILENO;
		upp->up_listensock = -1;
		break;

	case UART_TYPE_FILE:
		open_flags = O_WRONLY | O_CREAT;
		if (append_flag)
			open_flags |= O_APPEND;
		else
			open_flags |= O_TRUNC;
		fd = open(option_path, open_flags, 0600);
		if (fd < 0) {
			warn("%s: open of %s failed on device %s", __func__,
			    option_path, dev->pd_name);
			free(upp);
			upp = NULL;
			ret = false;
			goto out;
		}
		upp->up_fdinput = -1;
		upp->up_fdoutput = fd;
		upp->up_listensock = -1;
		break;

	case UART_TYPE_SOCKET:
		(void)unlink(option_path);
		fd = socket(PF_LOCAL, SOCK_STREAM, 0);
		if (fd < 0) {
			warn("%s: socket failed on device %s", __func__,
			    dev->pd_name);
			free(upp);
			upp = NULL;
			ret = false;
			goto out;
		}
		memset(&sun, 0, sizeof(sun));
		/* BSD-only: sun.sun_len = sizeof(sun); */
		sun.sun_family = AF_LOCAL;
		if (strlen(option_path) + 1 > sizeof(sun.sun_path)) {
			warnx("%s: path too long on device %s", __func__,
			    dev->pd_name);
			close(fd);
			free(upp);
			upp = NULL;
			ret = false;
			goto out;
		}
		strncpy(sun.sun_path, option_path, sizeof(sun.sun_path));
		if (bind(fd, (struct sockaddr *)&sun, sizeof(sun)) < 0) {
			warn("%s: bind failed on path %s device %s",
			    option_path, __func__, dev->pd_name);
			close(fd);
			free(upp);
			upp = NULL;
			ret = false;
			goto out;
		}
		if (listen(fd, -1) < 0) {
			warn("%s: listen failed on path %s device %s",
			    option_path, __func__, dev->pd_name);
			close(fd);
			free(upp);
			upp = NULL;
			ret = false;
			goto out;
		}
		upp->up_fdinput = upp->up_fdoutput = -1;
		upp->up_listensock = fd;
		break;

	case UART_TYPE_NULL:
		upp->up_fdinput = upp->up_fdoutput = -1;
		upp->up_listensock = -1;
		break;

	default:
		assert(0);
	}
	upp->up_reqfifo_empty = true;
	dev->pd_private = upp;

out:
	UDBG(upp, "returned - %d", ret);
	return (ret);
}

/*
 * When we simulate a UART using a socket, we potentially need to accept
 * connections, etc.  Implement this centrally.
 */
static void
uart_dev_listensock_poll(struct uart_private *upp)
{
	struct pollfd pollfd;
	int nfds;

	if (upp->up_fdinput != -1)
		return;
	memset(&pollfd, 0, sizeof(pollfd));
	pollfd.fd = upp->up_listensock;
	pollfd.events = POLLIN;
	nfds = poll(&pollfd, 1, 0);
	if (nfds < 0)
		err(1, "%s: poll on listen socket", __func__);
	if (nfds == 0)
		return;
	assert(pollfd.revents == POLLIN);
	upp->up_fdinput = upp->up_fdoutput = accept(upp->up_listensock, NULL,
	    NULL);
	assert(upp->up_fdinput != -1);
}

/*
 * When we simulate a UART using a socket and something goes wrong, use this
 * centralised connection close routine.
 */
static void
uart_dev_socket_cleanup(struct uart_private *upp)
{

	assert(upp->up_fdinput == upp->up_fdoutput);
	assert(upp->up_fdinput != -1);
	close(upp->up_fdinput);
	upp->up_fdinput = upp->up_fdoutput = -1;
}

/*
 * Per-class ready and fetch routines -- return true if *bp is valid, false
 * otherwise.
 */
static bool
uart_dev_file_fetch(struct uart_private *upp, uint8_t *bp)
{
	struct pollfd pollfd;
	ssize_t len;
	uint8_t b;
	int nfds;

	memset(&pollfd, 0, sizeof(pollfd));
	pollfd.fd = upp->up_fdinput;
	pollfd.events = POLLIN;
	nfds = poll(&pollfd, 1, 0);
	if (nfds < 0)
		err(1, "%s: poll", __func__);

	/*
	 * Note that files return POLLIN and also EOF, so handle that.
	 */
	if (nfds == 0 || !(pollfd.revents & POLLIN))
		return (false);
	len = read(upp->up_fdinput, &b, sizeof(b));
	if (len < 0)
		err(1, "%s: read", __func__);
	if (len == 0)
		return (false);
	*bp = b;
	return (true);
}

bool
uart_dev_file_fetch_ready(struct uart_private *upp)
{
	struct pollfd pollfd;
	int nfds;

	memset(&pollfd, 0, sizeof(pollfd));
	pollfd.fd = upp->up_fdinput;
	pollfd.events = POLLIN;
	nfds = poll(&pollfd, 1, 0);
	if (nfds < 0)
		err(1, "%s: poll", __func__);

	/*
	 * Note that files return POLLIN and also EOF, so handle that.
	 */
	if (nfds == 0 || !(pollfd.revents & POLLIN))
		return (false);
	return (true);
}

static bool
uart_dev_socket_fetch(struct uart_private *upp, uint8_t *bp)
{
	struct pollfd pollfd;
	ssize_t len;
	uint8_t b;
	int nfds;

	uart_dev_listensock_poll(upp);
	if (upp->up_fdinput == -1)
		return (false);

	memset(&pollfd, 0, sizeof(pollfd));
	pollfd.fd = upp->up_fdinput;
	pollfd.events = POLLIN;
	nfds = poll(&pollfd, 1, 0);
	if (nfds < 0)
		err(1, "%s: poll", __func__);
	if (nfds == 0)
		return (false);
	if (pollfd.revents & POLLIN) {
		len = read(upp->up_fdinput, &b, sizeof(b));
		if (len == sizeof(b)) {
			*bp = b;
			return (true);
		}
	}
	uart_dev_socket_cleanup(upp);
	return (false);
}

static bool
uart_dev_socket_fetch_ready(struct uart_private *upp)
{
	struct pollfd pollfd;
	int nfds;

	uart_dev_listensock_poll(upp);
	if (upp->up_fdinput == -1)
		return (false);

	memset(&pollfd, 0, sizeof(pollfd));
	pollfd.fd = upp->up_fdinput;
	pollfd.events = POLLIN;
	nfds = poll(&pollfd, 1, 0);
	if (nfds < 0)
		err(1, "%s: poll", __func__);
	if (nfds == 0)
		return (false);
	if (pollfd.revents & POLLIN)
		return (true);
	uart_dev_socket_cleanup(upp);
	return (false);
}

static bool
uart_dev_fetch(struct uart_private *upp, uint8_t *bp)
{
	bool data_valid;

	switch (upp->up_type) {
	case UART_TYPE_FILE:
	case UART_TYPE_STDIO:
		data_valid = uart_dev_file_fetch(upp, bp);
		break;

	case UART_TYPE_SOCKET:
		data_valid = uart_dev_socket_fetch(upp, bp);
		break;

	case UART_TYPE_NULL:
		data_valid = false;
		break;

	default:
		assert(0);
	}

	UDBG(upp, "returning %d", data_valid);
	return (data_valid);
}

static bool
uart_dev_fetch_ready(struct uart_private *upp)
{
	bool data_present;

	switch (upp->up_type) {
	case UART_TYPE_FILE:
	case UART_TYPE_STDIO:
		data_present = uart_dev_file_fetch_ready(upp);
		break;

	case UART_TYPE_SOCKET:
		data_present = uart_dev_socket_fetch_ready(upp);
		break;

	case UART_TYPE_NULL:
		data_present = false;
		break;

	default:
		assert(0);
	}

	UDBG(upp, "returning %d", data_present);
	return (data_present);
}

static bool
uart_dev_store_ready(struct uart_private *upp)
{
	bool store_ready;

	/* XXXRW: Possibly something more mature here. */
	store_ready = true;

	UDBG(upp, "returning %d", store_ready);
	return (store_ready);
}

static void
uart_dev_control_update(struct uart_private *upp)
{
	uint32_t control_old;

	/*
	 * The JTAG UART manual indicates that the RI and WI bits are
	 * "qualified" by the RE and WE bits -- as such, if a type of
	 * interrupt isn't enabled, we don't poll to see if the RI/WI bits
	 * should be set.
	 */
	control_old = upp->up_control;
	if (upp->up_fdoutput != -1 || upp->up_type == UART_TYPE_NULL)
		upp->up_control |= ALTERA_JTAG_UART_CONTROL_AC;
	else
		upp->up_control &= ~ALTERA_JTAG_UART_CONTROL_AC;
	if ((upp->up_control & ALTERA_JTAG_UART_CONTROL_RE) &&
	    uart_dev_fetch_ready(upp))
		upp->up_control |= ALTERA_JTAG_UART_CONTROL_RI;
	else
		upp->up_control &= ~ALTERA_JTAG_UART_CONTROL_RI;
	if ((upp->up_control & ALTERA_JTAG_UART_CONTROL_WE) &&
	    uart_dev_store_ready(upp))
		upp->up_control |= ALTERA_JTAG_UART_CONTROL_WI;
	else
		upp->up_control &= ~ALTERA_JTAG_UART_CONTROL_WI;
	if (upp->up_control != control_old)
		UDBG(upp, "returned - up_control from %08x to %08x",
		    control_old, upp->up_control);
}

static bool
uart_dev_interrupt_get(pism_device_t *dev)
{
	struct uart_private *upp;
	bool ret;

	/*
	 * If interrupts are requested, then poll to determine whether they
	 * should fire.
	 */
	ret = false;
	upp = dev->pd_private;
	if (dev->pd_irq != PISM_IRQ_NONE) {
		uart_dev_control_update(upp);
		if (upp->up_control & (ALTERA_JTAG_UART_CONTROL_RI |
		    ALTERA_JTAG_UART_CONTROL_WI))
			ret = true;
	}

	UDBG(upp, "returned - %d", ret);
	return (ret);
}

static bool
uart_dev_request_ready(pism_device_t *dev, pism_data_t *req)
{
	struct uart_private *upp;
	bool ret;

	upp = dev->pd_private;
	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		ret = true;
		break;

	case PISM_ACC_FETCH:
		/*
		 * We will not block on a read of the UART,
		 * even if there is no valid data.  We just
		 * indicate that data is not valid with the
		 * relevant bit.
		 */
		ret = upp->up_reqfifo_empty;
		break;

	default:
		assert(0);
	}

	UDBG(upp, "returned - %d", ret);
	return (ret);
}

static void
uart_dev_file_put(struct uart_private *upp, uint8_t b)
{

	(void)write(upp->up_fdoutput, &b, sizeof(b));
}

static void
uart_dev_socket_put(struct uart_private *upp, uint8_t b)
{
	ssize_t len;

	uart_dev_listensock_poll(upp);
	if (upp->up_fdoutput == -1)
		return;
	len = send(upp->up_fdoutput, &b, sizeof(b), MSG_NOSIGNAL);
	if (len != sizeof(b))
		uart_dev_socket_cleanup(upp);
}

static void
uart_dev_request_put(pism_device_t *dev, pism_data_t *req)
{
	struct uart_private *upp;
	uint64_t addr;
	uint32_t control_reg, new_control_reg;
	uint8_t b;
	int i;

	upp = dev->pd_private;
	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		addr = PISM_DEV_REQ_ADDR(dev, req);
		assert(addr == 0);
		if (PISM_REQ_BYTEENABLED(req, 0)) {
			b = PISM_REQ_BYTE(req, 0);
			UDBG(upp, "data byte written");
			switch (upp->up_type) {
			case UART_TYPE_FILE:
			case UART_TYPE_STDIO:
				uart_dev_file_put(upp, b);
				break;

			case UART_TYPE_SOCKET:
				uart_dev_socket_put(upp, b);
				break;

			case UART_TYPE_NULL:
				break;

			default:
				assert(0);
			}
		}

		/*
		 * Extract and store persistent control register state -- in
		 * particular, attempts to write the RE, WE, and AC bits.
		 * Accept writes only of the full 32-bit word, however --
		 * ignore partial writes.
		 */
		if (PISM_REQ_BYTEENABLED(req, 4) &&
		    PISM_REQ_BYTEENABLED(req, 5) &&
		    PISM_REQ_BYTEENABLED(req, 6) &&
		    PISM_REQ_BYTEENABLED(req, 7)) {
			for (i = 0; i < sizeof(uint32_t); i++) {
				((uint8_t *)&control_reg)[i] =
				    PISM_REQ_BYTE(req, i + 4);
			}
			control_reg = le32toh(control_reg);
			new_control_reg = upp->up_control;
			new_control_reg &=
			    ~ALTERA_JTAG_UART_CONTROL_PERSISTENT;
			new_control_reg |= (control_reg &
			    ALTERA_JTAG_UART_CONTROL_PERSISTENT);
			UDBG(upp, "control word written value %08x old %08x "
			    "new %08x", control_reg, upp->up_control,
			    new_control_reg);
			upp->up_control = new_control_reg;
		}
		break;

	case PISM_ACC_FETCH:
		assert(upp->up_reqfifo_empty);

		UDBG(upp, "fetch enqueued");
		memcpy(&upp->up_reqfifo, req, sizeof(upp->up_reqfifo));
		upp->up_reqfifo_empty = false;
		break;

	default:
		assert(0);
	}
}

static bool
uart_dev_response_ready(pism_device_t *dev)
{
	struct uart_private *upp;
	bool ret;

	upp = dev->pd_private;
	ret = !upp->up_reqfifo_empty;

	UDBG(upp, "returned - %d", ret);
	return (ret);
}

static pism_data_t
uart_dev_response_get(pism_device_t *dev)
{
	struct uart_private *upp;
	pism_data_t *req;
	uint32_t data_reg, control_reg;
	bool data_valid;
	uint8_t b;
	int i;

	upp = dev->pd_private;
	assert(!upp->up_reqfifo_empty);
	upp->up_reqfifo_empty = 1;
	req = &upp->up_reqfifo;

	switch (PISM_REQ_ACCTYPE(req)) {
	case PISM_ACC_STORE:
		/* XXXRW: This shouldn't happen, but perhaps does. */
		assert(0);
		break;

	case PISM_ACC_FETCH:
		/*
		 * As reading individual words has side effects, we can't just
		 * process the entire line unconditionally.  Handle each of
		 * the data and control word independently.
		 */
		if (PISM_REQ_BYTEENABLED(req, 0) ||
		    PISM_REQ_BYTEENABLED(req, 1) ||
		    PISM_REQ_BYTEENABLED(req, 2) ||
		    PISM_REQ_BYTEENABLED(req, 3)) {
			data_valid = uart_dev_fetch(upp, &b);
			if (data_valid)
				data_reg = b | ALTERA_JTAG_UART_DATA_RVALID;
			else
				data_reg = 0;
			UDBG(upp, "response data %08x", data_reg);
			data_reg = htole32(data_reg);
			for (i = 0; i < sizeof(data_reg); i++) {
				if (!(PISM_REQ_BYTEENABLED(req, i)))
					continue;
				PISM_REQ_BYTE(req, i) =
				    ((uint8_t *)&data_reg)[i];
			}
		}

		if (PISM_REQ_BYTEENABLED(req, 4) ||
		    PISM_REQ_BYTEENABLED(req, 5) ||
		    PISM_REQ_BYTEENABLED(req, 6) ||
		    PISM_REQ_BYTEENABLED(req, 7)) {
			/*
			 * Determine desired value for the control register.
			 * Always advertise a writable fifo size of 1 for the
			 * time being.
			 */
			uart_dev_control_update(upp);
			control_reg = upp->up_control;
			if (uart_dev_store_ready(upp))
				control_reg |= (1 <<
				    ALTERA_JTAG_UART_CONTROL_WSPACE_SHIFT);
			UDBG(upp, "response control %08x", control_reg);
			control_reg = htole32(control_reg);
			for (i = 0; i < sizeof(control_reg); i++) {
				if (!(PISM_REQ_BYTEENABLED(req, i +
				    sizeof(data_reg))))
					continue;
				PISM_REQ_BYTE(req, i + sizeof(data_reg)) =
				    ((uint8_t *)&control_reg)[i];
			}
		}
		for (i = sizeof(data_reg) + sizeof(control_reg);
		    i < PISM_DATA_BYTES; i++) {
			if (!(PISM_REQ_BYTEENABLED(req, i)))
				continue;
			PISM_REQ_BYTE(req, i) = 0x00;
		}
	}
	return (*req);
}

static bool
uart_dev_addr_valid(pism_device_t *dev, pism_data_t *req)
{

	return (true);
}

static const char *uart_option_list[] = {
	UART_OPTION_TYPE,
	UART_OPTION_PATH,
	NULL
};

PISM_MODULE_INFO(uart_module) = {
	.pm_name = "uart",
	.pm_option_list = uart_option_list,
	.pm_mod_init = uart_mod_init,
	.pm_dev_init = uart_dev_init,
	.pm_dev_interrupt_get = uart_dev_interrupt_get,
	.pm_dev_request_ready = uart_dev_request_ready,
	.pm_dev_request_put = uart_dev_request_put,
	.pm_dev_response_ready = uart_dev_response_ready,
	.pm_dev_response_get = uart_dev_response_get,
	.pm_dev_addr_valid = uart_dev_addr_valid,
};
