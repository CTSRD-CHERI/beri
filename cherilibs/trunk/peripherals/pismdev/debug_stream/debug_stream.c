/*-
 * Copyright (c) 2011 Wojciech A. Koszek
 * Copyright (c) 2011 Jonathan Woodruff
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2012 SRI International
 * Copyright (c) 2014 Colin Rothwell
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
#include <sys/socket.h>
#include <sys/un.h>

#include <assert.h>
#include <err.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <stdbool.h>
#include <unistd.h>
#include <termios.h>
#include <fcntl.h>
#include <errno.h>

#include "../../../include/cheri_debug.h"	/* XXXRW: better include path to use? */

/*-
 * This file implements a simple character stream for simulated versions of
 * the CHERI debug unit.
 *
 * TODO:
 *
 * 2. As with PISM, multiple bus instances should be supported, so that
 *    eventually, we can have one per CPU instance.
 * 3. It should be possible to configure debug busses using a simulator
 *    configuration file.
 * 5. Switch to POSIX async I/O to avoid any polling using OS interfaces.
 */

/*
 * PISM calls out to this module on every cycle.  However, we want to call out
 * to the OS's poll(2) routines only every (n) cycles.
 *
 * XXXRW: Unfortunately, this is not PISM.  Instead we rely on the input ready
 * interface being invoked every cycle.  If/when the debug unit is hooked up
 * to a PISM bus, we can switch to using the PSIM cycle tick event.
 * XXXCR: I don't think debug_cycle_counter is ever initialised...
 */
#define 		MAX_DEBUG_CYCLE_INTERVAL	10000
static uint64_t		 debug_cycle_interval[BERI_DEBUG_SOCKET_COUNT]
				= {10000, 10000};
static uint64_t		 debug_cycle_counter[BERI_DEBUG_SOCKET_COUNT];

/*
 * Listen socket and current accepted socket (if any).
 */

static char debug_listen_socket_path_unique[BERI_DEBUG_SOCKET_COUNT][1024];

static const char	*debug_listen_socket_path[BERI_DEBUG_SOCKET_COUNT];
static int		 debug_listen_socket[BERI_DEBUG_SOCKET_COUNT]
				= {-1, -1};

static int		 debug_session_socket[BERI_DEBUG_SOCKET_COUNT]
				= {-1, -1};
static bool		 debug_session_socket_writable[BERI_DEBUG_SOCKET_COUNT]
				= {false, false};

/*
 * If source "ready" returns true, then source "get" is not allowed to fail.
 * as such, if we poll and the session socket is readable, we immediately read
 * one character into a small buffer so that it is available for retrieval by
 * the CPU if we return "ready".
 */
static uint8_t		 debug_buffer[BERI_DEBUG_SOCKET_COUNT];
static bool		 debug_buffer_readable[BERI_DEBUG_SOCKET_COUNT]
				= {false, false};

/*
 * Rudimentary tracing facility for the debug socket.
 */
static bool		 debug_func_tracing_enabled[BERI_DEBUG_SOCKET_COUNT]
				= {false, false};
static bool		 debug_socket_tracing_enabled[BERI_DEBUG_SOCKET_COUNT]
				= {false, false};

#define	DEBUG_TRACE_FUNC(sn)	do {					\
	if (debug_func_tracing_enabled[(sn)])				\
		printf("(%u) %s\n", (sn), __func__);			\
} while (0)

#define	DEBUG_TRACE_SEND(sn, c)	do {					\
	if (debug_socket_tracing_enabled[(sn)])				\
		printf("(%u) %s: sent 0x%02x\n", (sn), __func__, (c));	\
} while (0)

#define	DEBUG_TRACE_RECV(sn, c)	do {					\
	if (debug_socket_tracing_enabled[(sn)])				\
		printf("(%u) %s: received 0x%02x\n", (sn), __func__, (c)); \
} while (0)

static void
debug_session_socket_close(uint8_t stream_no)
{

	DEBUG_TRACE_FUNC(stream_no);

	assert(debug_session_socket[stream_no] != -1);

	close(debug_session_socket[stream_no]);
	debug_session_socket[stream_no] = -1;
	debug_session_socket_writable[stream_no] = 0;
}

/*
 * We need to poll both listen and accepted sockets at regular intervals for
 * I/O (or the possibility of I/O).  However, we don't want to do it every
 * cycle or the simulator will burn lots of CPU in the kernel.
 */
static void
debug_poll(uint8_t stream_no)
{
	struct pollfd pollfd;
	ssize_t len;
	int ret;

	DEBUG_TRACE_FUNC(stream_no);

	debug_cycle_counter[stream_no]++;
	if (debug_cycle_counter[stream_no] % debug_cycle_interval[stream_no]
			!= 0)
		return;

	if (debug_listen_socket[stream_no] == -1)
		return;
	memset(&pollfd, 0, sizeof(pollfd));
	pollfd.fd = debug_listen_socket[stream_no];
	pollfd.events = POLLIN;
	ret = poll(&pollfd, 1, 0);
	if (ret == -1)
		err(1, "(%u) %s: poll on listen socket", stream_no, __func__);
	if (ret == 1) {
		assert(pollfd.revents == POLLIN);
		debug_session_socket[stream_no] =
			accept(debug_listen_socket[stream_no], NULL, NULL);
		assert(debug_session_socket[stream_no] != -1);
	}

	if (debug_session_socket[stream_no] == -1)
		return;
	memset(&pollfd, 0, sizeof(pollfd));
	pollfd.fd = debug_session_socket[stream_no];
	pollfd.events = POLLIN | POLLOUT;
	ret = poll(&pollfd, 1, 0);
	if (ret == -1)
		err(1, "(%u) %s: poll on accepted socket", stream_no, __func__);
	if (ret == 0)
		return;
	assert(ret == 1);

	/* XXXRW: Handle POLLHUP? */

	if (pollfd.revents & POLLOUT)
		debug_session_socket_writable[stream_no] = true;

	/*
	 * If the session socket was readable and we haven't already buffered
	 * an input character, read and buffer one now.
	 */
	if ((pollfd.revents & POLLIN) && !debug_buffer_readable[stream_no]) {
		len = read(debug_session_socket[stream_no],
			   &debug_buffer[stream_no],
			   sizeof(debug_buffer[stream_no]));
		if (len > 0) {
			assert(len == sizeof(debug_buffer[stream_no]));
			debug_buffer_readable[stream_no] = true;
			DEBUG_TRACE_RECV(stream_no, debug_buffer[stream_no]);
			debug_cycle_interval[stream_no] = 10;
		} else if (len == 0) {
			debug_session_socket_close(stream_no);
			if (debug_cycle_interval[stream_no] < MAX_DEBUG_CYCLE_INTERVAL)
				debug_cycle_interval[stream_no] *= 2;
			else debug_cycle_interval[stream_no] = MAX_DEBUG_CYCLE_INTERVAL;
		} else {
			warn("(%u) %s: DEBUG POLL ERROR: len: %zd", stream_no,
				__func__, len);
		}
	}
}

bool
debug_stream_init(uint8_t stream_no)
{
	struct sockaddr_un sun;

	DEBUG_TRACE_FUNC(stream_no);

	assert(stream_no < BERI_DEBUG_SOCKET_COUNT);

	const char *debug_socket_path_env = (stream_no == 0 ?
		BERI_DEBUG_SOCKET_PATH_ENV_0 :
		BERI_DEBUG_SOCKET_PATH_ENV_1);

	debug_socket_tracing_enabled[stream_no] =
	    (getenv(BERI_DEBUG_SOCKET_TRACING_ENV) != NULL);

	debug_listen_socket[stream_no] = socket(PF_LOCAL, SOCK_STREAM, 0);
	if (debug_listen_socket[stream_no] == -1) {
		warn("%s: socket", __func__);
		return (false);
	}
	debug_listen_socket_path[stream_no] = getenv(debug_socket_path_env);
	if (debug_listen_socket_path[stream_no] == NULL) {
		debug_listen_socket_path[stream_no] = (stream_no == 0 ?
			BERI_DEBUG_SOCKET_PATH_DEFAULT_0 :
			BERI_DEBUG_SOCKET_PATH_DEFAULT_1);
		snprintf(debug_listen_socket_path_unique[stream_no],
		    sizeof(debug_listen_socket_path_unique[stream_no]), "%s%d",
		    debug_listen_socket_path[stream_no], getuid());
		debug_listen_socket_path[stream_no] =
			debug_listen_socket_path_unique[stream_no];
	}
	printf("stream%d: %s\n", stream_no, debug_listen_socket_path[stream_no]);
	if (strlen(debug_listen_socket_path[stream_no]) > sizeof(sun.sun_path)-1) {
		err(1,"(%u) %s: UNIX domain socket path %s too long (> %lud bytes)", stream_no, __func__,
			debug_listen_socket_path[stream_no], sizeof(sun.sun_path)-1);
	}
	(void)unlink(debug_listen_socket_path[stream_no]);
	memset(&sun, 0, sizeof(sun));
	sun.sun_family = AF_LOCAL;
	/* BSD only: sun.sun_len = sizeof(sun); */
	strncpy(sun.sun_path, debug_listen_socket_path[stream_no],
	    sizeof(sun.sun_path) -1);
	if (bind(debug_listen_socket[stream_no], (struct sockaddr *)&sun,
			sizeof(sun)) < 0) {
		err(1,"(%u) %s: bind(%s)", stream_no, __func__, debug_listen_socket_path[stream_no]);
	}
	if (listen(debug_listen_socket[stream_no], -1) < 0) {
		warn("(%u) %s: listen", stream_no, __func__);
		goto out;
	}
	return (true);

out:
	close(debug_listen_socket[stream_no]);
	debug_listen_socket[stream_no] = -1;
	return (false);
}

bool
debug_stream_sink_ready(uint8_t stream_no)
{

	DEBUG_TRACE_FUNC(stream_no);

	return (debug_session_socket_writable[stream_no]);
}

void
debug_stream_sink_put(uint8_t stream_no, uint8_t ch)
{
	ssize_t len;

	DEBUG_TRACE_FUNC(stream_no);

	/*
	 * Note: depending on order of operations, we could get here with the
	 * socket closed.  There is no way to report an error here, so we eat
	 * it if one occurs.
	 */
	if (debug_session_socket[stream_no] == -1)
		return;
	DEBUG_TRACE_SEND(stream_no, ch);
	len = send(debug_session_socket[stream_no], &ch, sizeof(ch),
			MSG_NOSIGNAL);
	if (len < 0 || len == 0)
		debug_session_socket_close(stream_no);
	else
		assert(len == sizeof(ch));
	debug_session_socket_writable[stream_no] = false;
}

bool
debug_stream_source_ready(uint8_t stream_no)
{

	DEBUG_TRACE_FUNC(stream_no);

	debug_poll(stream_no);		/* Called once per cycle here. */

	/*
	 * The check here is not whether the socket is present and readable,
	 * but rather, whether we have already buffered an input character,
	 * which may be the case even if the socket has been closed or is not
	 * readable.
	 */
	return (debug_buffer_readable[stream_no]);
}

uint8_t
debug_stream_source_get(uint8_t stream_no)
{

	DEBUG_TRACE_FUNC(stream_no);

	/* XXXRW: Hopefully this is true? */
	assert(debug_buffer_readable[stream_no]);

	debug_buffer_readable[stream_no] = false;
	return (debug_buffer[stream_no]);
}
