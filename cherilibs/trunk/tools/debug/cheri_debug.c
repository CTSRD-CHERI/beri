/*-
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2011-2013 Jonathan Woodruff
 * Copyright (c) 2012-2013 SRI International
 * Copyright (c) 2012 Simon W. Moore
 * Copyright (c) 2012-2014 Robert Norton
 * Copyright (c) 2012-2014 Bjoern A. Zeeb
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2013 Jonathan Anderson
 * 
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
 * Utility routines for interacting with the BERI debug unit.
 *
 * TODO:
 *
 * 2. This implementation is specific to big endian targets; it would not be
 *    much work to make it function with little endian targets as well.  It is
 *    quite important that we work from both big and little endian hosts.
 *    Most endianness assumptions are in the consumer of this library, but
 *    notice an endianness assumption in the automatic generation of MIPS
 *    instructions as part of the register query APIs, as well as in
 *    sub-register size loads/stores, where endianness conversion is required
 *    to properly truncate for the caller.
 * 4. Implement additional memory load and store operations; right now we
 *    implement only ld.
 */

#include <arpa/inet.h>

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/wait.h>

#ifdef __FreeBSD__
#include <sys/endian.h>
#include <sys/limits.h>

#include <netinet/in.h>
#else
#include <limits.h>
#endif

#include <assert.h>
#include <err.h>
#include <errno.h>
#ifdef BERI_NETFPGA
#include <sys/ioctl.h>
#include <fcntl.h>
#include <string.h>
#endif
#include <inttypes.h>
#include <poll.h>
#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

#include <stdio.h>
#include <string.h>

#include "../../include/cheri_debug.h"
#include "altera_systemconsole.h"
#include "cherictl.h"
#include "berictl_netfpga.h"

#define	BREAKRING_SIZE	4
struct beri_debug {
	/*
	 * Connection-related state.
	 */
	int		bd_fd;		/* File descriptor for session. */
	pid_t		bd_pid;

	/*
	 * Breakpoint-related state.
	 */
	u_int		bd_breakpoint_fired;	/* bd_breakpoint_addr valid? */
	uint64_t	bd_breakpoint_addr;

	/*
	 * Pipeline state (BERI2 only)
	 */
	u_int		bd_pipeline_state;

#define	BERI_NETFPGA_IOCTL	0x00000001
#define	BERI_BERI2		0x00000002
#define	BERI_NO_PAUSE_RESUME	0x00000004
	uint32_t	bd_flags;
};

#define	BERI_DEBUG_PAYLOAD_MAX	(1 << (((sizeof(uint8_t) * 8) - 1) - 1))

static struct beri_debug *
beri_debug_new(void)
{
	struct beri_debug *bdp;

	bdp = calloc(sizeof(*bdp), 1);
	bdp->bd_fd = -1;
	bdp->bd_pid = 0;
	bdp->bd_pipeline_state = BERI2_DEBUG_STATE_UNKNOWN;
	return (bdp);
}

static void
beri_debug_close_internal(struct beri_debug *bdp)
{
	int status;

	bdp->bd_flags = 0;
	bdp->bd_pipeline_state = BERI2_DEBUG_STATE_UNKNOWN;

	if (bdp->bd_pid > 0) {
		if (wait4(bdp->bd_pid, &status, WNOHANG, NULL) != bdp->bd_pid)
			kill(bdp->bd_pid, SIGKILL);
		else if (WIFEXITED(status))
			warnx("process exited with status %d", WEXITSTATUS(status));
		else if (WIFSIGNALED(status))
			warnx("child killed by signal %d", WTERMSIG(status));
	} else if (bdp->bd_pid < 0) {
		/* 
		 * Don't try checking on process groups, just try to
		 * kill them.
		 */
		kill(bdp->bd_pid, SIGKILL);
	}
	bdp->bd_pid = 0;

	if (bdp->bd_fd == -1)
		return;
	close(bdp->bd_fd);
	bdp->bd_fd = -1;
}

static void
beri_debug_destroy(struct beri_debug *bdp)
{

	beri_debug_close_internal(bdp);
	free(bdp);
}

int
beri_debug_cleanup(void)
{
	pid_t pid;

	/*
	 * Kill any system-consoles we started previously and nuke
	 * the port and pid files.
	 */
	altera_sc_get_status(&pid, NULL);
	if (pid > 0)
		altera_sc_stop(pid);
	//altera_sc_clear_status();
        
	return (BERI_DEBUG_SUCCESS);
}

static void
beri_debug_client_breakpoint_fired(struct beri_debug *bdp, uint64_t addr)
{

	bdp->bd_breakpoint_fired = 1;
	bdp->bd_breakpoint_addr = addr;
}

int
beri_debug_getfd(struct beri_debug *bdp)
{

	return (bdp->bd_fd);
}

int
beri_debug_is_netfpga(struct beri_debug *bdp)
{

	assert(bdp != NULL);
	return ((bdp->bd_flags & BERI_NETFPGA_IOCTL) == BERI_NETFPGA_IOCTL);
}

int
beri_debug_client_open_path(struct beri_debug **bdpp, const char *pathp,
    uint32_t oflags)
{
	struct beri_debug *bdp;
	char *endp;
	unsigned long port;

	bdp = beri_debug_new();

	if (oflags & BERI_DEBUG_CLIENT_OPEN_FLAGS_NO_PAUSE_RESUME)
		bdp->bd_flags |= BERI_NO_PAUSE_RESUME;

	if (oflags & BERI_DEBUG_CLIENT_OPEN_FLAGS_BERI2)
		bdp->bd_flags |= BERI_BERI2;

#ifdef BERI_NETFPGA
	if (oflags & BERI_DEBUG_CLIENT_OPEN_FLAGS_NETFPGA) {
		bdp->bd_fd = open(NETFPGA_DEV_PATH, O_RDWR);
		if (bdp->bd_fd == -1) {
			beri_debug_destroy(bdp);
			return (BERI_DEBUG_ERROR_SOCKET);
		}
		bdp->bd_flags |= BERI_NETFPGA_IOCTL;
		*bdpp = bdp;
		return (BERI_DEBUG_SUCCESS);
	}
#endif

	/*
	 * Try to determine if we got a port number or a posix local socket
	 * path.  Err on the posix local socket case, which used to be the
	 * only case supported.
	 * XXX-BZ we could extend this to also parse IP addresses for remote
	 * debugging or IPv6 support.
	 */
	errno = 0;
	port = strtoul(pathp, &endp, 10);
	if (port != ULONG_MAX && errno == 0 && endp != NULL && *endp == '\0') {
		/* We are connecting to system-console using TCP/IPv4. */
		struct sockaddr_in sin;

		bdp->bd_fd = socket(PF_INET, SOCK_STREAM, 0);
		if (bdp->bd_fd == -1) {
			beri_debug_destroy(bdp);
			return (BERI_DEBUG_ERROR_SOCKET);
		}
		memset(&sin, 0, sizeof(sin));
		sin.sin_family = AF_INET;
#ifdef __FreeBSD__
		sin.sin_len = sizeof(sin);
#endif
		if (inet_pton(PF_INET, "127.0.0.1", &sin.sin_addr) != 1) {
			beri_debug_destroy(bdp);
			return (BERI_DEBUG_ERROR_SOCKET);
		}
		sin.sin_port = htons(port);
		if (connect(bdp->bd_fd, (struct sockaddr *)&sin,
		    sizeof(sin)) < 0) {
			beri_debug_destroy(bdp);
			return (BERI_DEBUG_ERROR_CONNECT);
		}
	
	} else {
		/* Posix Local socket. */
		struct sockaddr_un sun;

		bdp->bd_fd = socket(PF_LOCAL, SOCK_STREAM, 0);
		if (bdp->bd_fd == -1) {
			beri_debug_destroy(bdp);
			return (BERI_DEBUG_ERROR_SOCKET);
		}
		memset(&sun, 0, sizeof(sun));
		sun.sun_family = AF_LOCAL;
#ifdef __FreeBSD__
		sun.sun_len = sizeof(sun);
#endif
		strncpy(sun.sun_path, pathp, sizeof(sun.sun_path) - 1);
		if (connect(bdp->bd_fd, (struct sockaddr *)&sun,
		    sizeof(sun)) < 0) {
			beri_debug_destroy(bdp);
			return (BERI_DEBUG_ERROR_CONNECT);
		}
	}
	*bdpp = bdp;
	return (BERI_DEBUG_SUCCESS);
}

int
beri_debug_client_open(struct beri_debug **bdpp, uint32_t oflags)
{
	const char *pathp;
	char socket_path[1024];
	pathp = getenv(BERI_DEBUG_SOCKET_PATH_ENV_0);
	if (pathp == NULL) {
		pathp = BERI_DEBUG_SOCKET_PATH_DEFAULT_0;
		snprintf(socket_path, sizeof(socket_path), "%s%d", pathp,
		    getuid());
		pathp = socket_path;
	}
	return (beri_debug_client_open_path(bdpp, pathp, oflags));
}

#ifndef	__DECONST
#define	__DECONST(type, var)	((type)(uintptr_t)(const void *)(var)) 
#endif

int
beri_debug_client_open_nios(struct beri_debug **bdpp, const char *cablep,
    uint32_t oflags)
{
	struct beri_debug *bdp;
	int sockets[2];
	char *nios_path;
	char *argv[] = {
		"nios2-terminal-fast", "-q", "--no-quit-on-ctrl-d",
		"--instance", "0", NULL, NULL, NULL };

	if ((nios_path = getenv("BERICTL_NIOS2_TERMINAL")) != NULL)
		argv[0] = nios_path;

	assert(!(oflags & BERI_DEBUG_CLIENT_OPEN_FLAGS_NETFPGA));

	if (cablep != NULL && *cablep != '\0') {
		argv[5] = "--cable";
		argv[6] = __DECONST(char *, cablep);
	}
	
	bdp = beri_debug_new();

	if (oflags & BERI_DEBUG_CLIENT_OPEN_FLAGS_BERI2)
		bdp->bd_flags |= BERI_BERI2;

	if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == -1) {
		beri_debug_destroy(bdp);
		return (BERI_DEBUG_ERROR_SOCKETPAIR);
	}
	bdp->bd_pid = fork();
	if (bdp->bd_pid < 0) {
		beri_debug_destroy(bdp);
		return (BERI_DEBUG_ERROR_FORK);
	} else if (bdp->bd_pid != 0) {
		close(sockets[1]);
		bdp->bd_fd = sockets[0];
		/* XXX: set up signal handler for child? */
	} else {
		close(sockets[0]);
		if (dup2(sockets[1], STDIN_FILENO) == -1 ||
		    dup2(sockets[1], STDOUT_FILENO) == -1)
			err(1, "dup2");
#ifdef __FreeBSD__
		closefrom(3);
#else
		/* XXX: weaker than ideal cleanup, but probably harmless. */
		close(sockets[1]);
#endif
		execvp(argv[0], argv);
		if (errno == ENOENT && argv[0] != nios_path) {
			argv[0] = "nios2-terminal";
			execvp(argv[0], argv);
		}
		if (errno == ENOENT)
			err(1, "nios2-terminal not found in PATH");
		err(1, "execvp");
	}
	*bdpp = bdp;
	return (BERI_DEBUG_SUCCESS);
}

int
beri_debug_client_open_sc(struct beri_debug **bdpp, uint32_t oflags)
{
	int pid, port;
	struct beri_debug *bdp;
	struct sockaddr_in sin;

	assert(!(oflags & BERI_DEBUG_CLIENT_OPEN_FLAGS_NETFPGA));

	bdp = beri_debug_new();

	if (oflags & BERI_DEBUG_CLIENT_OPEN_FLAGS_BERI2)
		bdp->bd_flags |= BERI_BERI2;

	altera_sc_get_status(&pid, &port);
	if (pid <= 0) {
		printf("Starting system-console...\n");
		if (altera_sc_start(&pid, &port) == -1) {
			beri_debug_destroy(bdp);
			return (BERI_DEBUG_ERROR_FORK);
		}
		if (altera_sc_write_status(pid, port) == -1) {
			/*
			 * Got a server, but failed to cache it's pid and/or
			 * port so we need to kill it when we're done.
			 * system-console is multiple processes and we've set
			 * it up as the lead of its process group so store
			 * the pgid here so they all get killed.
			 */
			bdp->bd_pid = -pid;
		}
	}

	bdp->bd_fd = socket(PF_INET, SOCK_STREAM, 0);
	if (bdp->bd_fd == -1) {
		beri_debug_destroy(bdp);
		return (BERI_DEBUG_ERROR_SOCKET);
	}
	memset(&sin, 0, sizeof(sin));
	sin.sin_family = AF_INET;
#ifdef __FreeBSD__
	sin.sin_len = sizeof(sin);
#endif
	if (inet_pton(PF_INET, "127.0.0.1", &sin.sin_addr) != 1) {
		beri_debug_destroy(bdp);
		return (BERI_DEBUG_ERROR_SOCKET);
	}
	sin.sin_port = htons(port);
	if (connect(bdp->bd_fd, (struct sockaddr *)&sin, sizeof(sin)) < 0) {
		beri_debug_destroy(bdp);
		return (BERI_DEBUG_ERROR_CONNECT);
	}

	*bdpp = bdp;
	return (BERI_DEBUG_SUCCESS);
}

static int
beri_debug_client_write(struct beri_debug *bdp, void *bufferp,
    size_t writelen)
{
	ssize_t len, total;
	if (debugflag) {
		printf("client write:");
		for (len=0; len<writelen;len++)
		  printf(" 0x%.2x", (unsigned int)((unsigned char *)bufferp)[len]);
		printf("\n");
	}
	total = 0;
	do {
		len = send(bdp->bd_fd, bufferp + total, writelen - total,
		    MSG_NOSIGNAL);
		if (len <= 0) {
			beri_debug_close_internal(bdp);
			return (BERI_DEBUG_ERROR_SEND);
		}
		total += len;
	} while (total < writelen);
	return (BERI_DEBUG_SUCCESS);
}

#ifdef BERI_NETFPGA
static int
beri_debug_client_write_netfpga_ioctl(struct beri_debug *bdp, uint8_t command,
    void *bufferp, size_t bufferlen)
{
	size_t l;
	uint8_t *vp;

	if (bufferlen > NETFPGA_IOCTL_PAYLOAD_MAX)
		return (BERI_DEBUG_ERROR_DATA_TOOBIG);

	/*
	 * The 'axi-debug bridge protocol' goes as follows:
	 * 1 clear the registers
	 * 2 write command, length and payload
	 * 3 write length (entire T+L+V) to pass to beridebug core
	 * 4 tell axi-debug bridge to send it off
	 *[5 read answer back, elsewhere]
	 */

	/* ioctl values are encoded as (io_addr) << 32 | (value & 0xffffffff) */
	NETFPGA_IOCTL_WR(NETFPGA_AXI_DEBUG_BRIDGE_WR, command);
	NETFPGA_IOCTL_WR(NETFPGA_AXI_DEBUG_BRIDGE_WR, bufferlen);
	l = bufferlen;
	vp = (uint8_t *)bufferp;
	while (l > 0) {
		NETFPGA_IOCTL_WR(NETFPGA_AXI_DEBUG_BRIDGE_WR, *vp);
		vp++, l--;
	}
	NETFPGA_IOCTL_WR(NETFPGA_AXI_DEBUG_BRIDGE_WR_GO, 1);

	/* Give the system a chance to catch up. */
	usleep(1000);

	return (BERI_DEBUG_SUCCESS);
}
#endif

/*
 * Write out a BERI debug unit packet including command, length, and payload.
 *
 * XXXRW: This should not be a public function.
 */
int
beri_debug_client_packet_write(struct beri_debug *bdp, uint8_t command,
    void *bufferp, size_t bufferlen)
{
	int ret;
	uint8_t b;

	if (bufferlen > BERI_DEBUG_PAYLOAD_MAX)
		return (BERI_DEBUG_ERROR_DATA_TOOBIG);
#ifdef BERI_NETFPGA
	if (beri_debug_is_netfpga(bdp))
		return (beri_debug_client_write_netfpga_ioctl(bdp,
		    command, bufferp, bufferlen));
#endif
	ret = beri_debug_client_write(bdp, &command, sizeof(command));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	b = bufferlen;
	ret = beri_debug_client_write(bdp, &b, sizeof(b));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	if (bufferlen != 0)
		return (beri_debug_client_write(bdp, bufferp, bufferlen));
	return (BERI_DEBUG_SUCCESS);
}

#ifdef BERI_NETFPGA
static int
beri_debug_client_read_netfpga_ioctl(struct beri_debug *bdp, void *bufferp,
    size_t readlen)
{
	uint64_t rv;
	uint8_t *p;

	if (readlen == 0)
		return (BERI_DEBUG_SUCCESS);

	p = bufferp;
	do {
		NETFPGA_IOCTL_RD(rv, NETFPGA_AXI_DEBUG_BRIDGE_RD);
		*p = rv & 0xff;
		p++;
		readlen--;
	} while (readlen > 0);

	return (BERI_DEBUG_SUCCESS);
}

static int
beri_debug_client_netfpga_drain(struct beri_debug *bdp)
{
	uint64_t rv;
	int ret;

	do {
		ret = ioctl(bdp->bd_fd, NETFPGA_IOCTL_CMD_READ_REG, &rv);
		if (ret == -1)
			return (BERI_DEBUG_ERROR_READ);
	} while ((rv & NETFPGA_AXI_FIFO_RD_BYTE_VALID) ==
	    NETFPGA_AXI_FIFO_RD_BYTE_VALID);

	return (BERI_DEBUG_SUCCESS);
}
#endif

/*
 * The debug unit is stateful in only well-defined ways; however, if for some
 * reason we start a new debug session and a previous session hadn't
 * terminated cleanly, we might need to drain any data remaining on the debug
 * socket.  This doesn't handle interrupted sends to the debug unit, only
 * interrupted receives, but that is a more common case.
 */
int
beri_debug_client_drain(struct beri_debug *bdp)
{
	struct pollfd pollfd;
	ssize_t len;
	uint8_t v;
	int ret;

#ifdef BERI_NETFPGA
	if ((bdp->bd_flags & BERI_NETFPGA_IOCTL) == BERI_NETFPGA_IOCTL)
		return (beri_debug_client_netfpga_drain(bdp));
#endif

	do {
		memset(&pollfd, 0, sizeof(pollfd));
		pollfd.fd = bdp->bd_fd;
		pollfd.events = POLLIN;
		ret = poll(&pollfd, 1, 0);
		if (ret < 0)
			return (BERI_DEBUG_ERROR_READ);
		if (ret == 1) {
			if (!(pollfd.revents & POLLIN))
				return (BERI_DEBUG_ERROR_READ);
			len = recv(bdp->bd_fd, &v, sizeof(v), 0);
			if (len != sizeof(v))
				return (BERI_DEBUG_ERROR_READ);
		}
	} while (ret == 1);
	return (BERI_DEBUG_SUCCESS);
}

static int
beri_debug_client_read(struct beri_debug *bdp, void *bufferp,
    size_t readlen)
{
	ssize_t len, total;

#ifdef BERI_NETFPGA
	if ((bdp->bd_flags & BERI_NETFPGA_IOCTL) == BERI_NETFPGA_IOCTL)
		return (beri_debug_client_read_netfpga_ioctl(bdp,
		    bufferp, readlen));
#endif

	total = 0;
	do {
		len = recv(bdp->bd_fd, bufferp + total, readlen - total,
		    MSG_WAITALL);
		if (len <= 0) {
			beri_debug_close_internal(bdp);
			return (BERI_DEBUG_ERROR_READ);
		}
		total += len;
	} while (total < readlen);
	if (debugflag) {
		printf("client read:");
		for (len=0;len<total;len++) {
			printf(" 0x%.2x", (unsigned int) (((unsigned char *)bufferp)[len]));
		}
		printf("\n");
	}
	return (BERI_DEBUG_SUCCESS);
}

/*
 * Variant on a read of (readlen) bytes that reads the bytes and compares
 * them with the passed buffer, rather than reading them into the passed
 * buffer.
 */
static int
beri_debug_client_read_expect(struct beri_debug *bdp, void *bufferp,
    size_t readlen)
{
	size_t count;
	int ret;
	char ch;

	for (count = 0; count < readlen; count++) {
		ret = beri_debug_client_read(bdp, &ch, sizeof(ch));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		if (ch != *((char *)bufferp + count)) {
		  fprintf(stderr, "want:%d got:%d\n", *((char *)bufferp + count), ch);
		  return (BERI_DEBUG_ERROR_DATA_UNEXPECTED); }
	}
	return (BERI_DEBUG_SUCCESS);
}

/*
 * Read in a BERI debug unit packet including command, length, and payload.
 * Check that the command and payload length are as requested by the caller.
 *
 * XXXRW: Currently, this doesn't handle async events or reject messages, but
 * will in the future.
 */
static int
beri_debug_client_packet_read_excode(struct beri_debug *bdp,
    uint8_t command, void *bufferp, size_t bufferlen, uint8_t *excodep)
{
	uint64_t addr;
	int ret;
	uint8_t b;
	uint8_t replyop;
	uint8_t excode;
	uint8_t invalidOp, breakpointFiredOp, exceptionOp;

	if (bufferlen > BERI_DEBUG_PAYLOAD_MAX)
		return (BERI_DEBUG_ERROR_DATA_TOOBIG);
restart:
	ret = beri_debug_client_read(bdp, &replyop, sizeof(replyop));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	if (bdp->bd_flags & BERI_BERI2) {
		breakpointFiredOp = BERI2_DEBUG_EV_BREAKPOINT_FIRED;
		exceptionOp = BERI2_DEBUG_EV_EXCEPTION;
		/* On cheri2, invalid op is just another exception */
		invalidOp = BERI2_DEBUG_EV_EXCEPTION;
	} else {
		invalidOp = BERI_DEBUG_ER_INVALID;
		breakpointFiredOp = BERI_DEBUG_EV_BREAKPOINT_FIRED;
		exceptionOp = BERI_DEBUG_ER_EXCEPTION;
	}
	
	if (replyop == exceptionOp) {
		/*
		 * Currently, only the BERI_DEBUG_OP_EXECUTE_INSTRUCTION can
		 * return an exception, but we allow for the possibility of
		 * others doing so in the future.  Because the exception case
		 * may return a different payload size than the original
		 * command, separate handling of the length field as required
		 * as well.  We must fully parse the exception reply packet,
		 * even if the caller doesn't expect an exception -- otherwise
		 * the protocol will be left in an inconsistent state.
		 */
		b = sizeof(excode);
		ret = beri_debug_client_read_expect(bdp, &b, sizeof(b));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		ret = beri_debug_client_read(bdp, &excode, sizeof(excode));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		if (excodep != NULL)
			*excodep = excode;
		return (BERI_DEBUG_ERROR_EXCEPTION);
	} else if (replyop == invalidOp)
		return (BERI_DEBUG_ERROR_UNSUPPORTED);
	else if (replyop == breakpointFiredOp) {
		/*
		 * There are two relevant cases for breakpoints.  In the
		 * first, the caller is actively awaiting an asynchronous
		 * breakpoint notification.  In that case, handle the
		 * received notification as a normal request.  In the other
		 * case, a breakpoint notification is not expected, so store
		 * it for later use and loop back to read the next (likely
		 * expected) packet.
		 */
		if (command == BERI_DEBUG_EV_BREAKPOINT_FIRED)
			goto readreply;
		b = sizeof(addr);
		ret = beri_debug_client_read_expect(bdp, &b, sizeof(b));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		ret = beri_debug_client_read(bdp, &addr, sizeof(addr));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		beri_debug_client_breakpoint_fired(bdp, addr);
		/* XXXRW: Dubious use of goto. */
		goto restart;
	}
readreply:
	b = bufferlen;
	ret = beri_debug_client_read_expect(bdp, &b, sizeof(b));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	if (bufferlen != b) {
		warnx("Expected to read %zu, found %d", bufferlen, b);
		return (BERI_DEBUG_USAGE_ERROR);
	}
	if (bufferlen != 0)
		ret = beri_debug_client_read(bdp, bufferp, bufferlen);
	return (ret);
}

static int
beri_debug_client_packet_read(struct beri_debug *bdp, uint8_t command,
    void *bufferp, size_t bufferlen)
{

	return (beri_debug_client_packet_read_excode(bdp, command, bufferp,
	    bufferlen, NULL));
}

/*
 * A number of our debug protocol transactions consist of a command and an
 * ACK.  Provide a simple routine to do both sides of the transaction.
 */
static int
beri_debug_client_packet_simple(struct beri_debug *bdp, uint8_t command)
{
	int ret;

	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0));
}

void
beri_debug_client_close(struct beri_debug *bdp)
{

	beri_debug_destroy(bdp);
}

/*
 * The BERI debug unit allows 64-bit MIPS instructions to be inserted into
 * the pipeline in order to perform various operations, including moving
 * registers, loading memory, storing memory, etc.  We provide an (extremely)
 * minimalist MIPS assembler here to support debuggers performing these
 * operations.
 *
 * Instructions are returned in big endian format, even though most other
 * parts of the BERI debugging API assume native endian.  This is because we
 * will generate and transmit instructions from entirely within the library.
 * If we want to support little endian MIPS processor targets, then a flag
 * will need to be passed to meta-operation APIs to indicate the target
 * endianness.
 */
#define	MIPS64_TYPE_SHIFT		26
#define	MIPS64_MASK_REG			0x1f
#define	MIPS64_INS_DADDU_TYPE		0x00
#define	MIPS64_INS_DADDU_RD_SHIFT	11
#define	MIPS64_INS_DADDU_RS_SHIFT	21
#define	MIPS64_INS_DADDU_RT_SHIFT	16
#define	MIPS64_INS_DADDU_OP		0x2d
int
mips64be_make_ins_daddu(u_int rd, u_int rs, u_int rt, uint32_t *insp)
{
	uint32_t v;

	if ((rd & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rs & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	v = MIPS64_INS_DADDU_TYPE << MIPS64_TYPE_SHIFT;
	v |= rd << MIPS64_INS_DADDU_RD_SHIFT;
	v |= rs << MIPS64_INS_DADDU_RS_SHIFT;
	v |= rt << MIPS64_INS_DADDU_RT_SHIFT;
	v |= MIPS64_INS_DADDU_OP;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_JR_TYPE		0x0
#define	MIPS64_INS_JR_RS_SHIFT		21
#define	MIPS64_INS_JR_JR		8
int
mips64be_make_ins_jr(u_int rs, uint32_t *insp)
{
	uint32_t v;

	if ((rs & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	v = MIPS64_INS_JR_TYPE << MIPS64_TYPE_SHIFT;
	v |= rs << MIPS64_INS_JR_RS_SHIFT;
	v |= MIPS64_INS_JR_JR;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

int
mips64be_make_ins_move(u_int rd, u_int rs, uint32_t *insp)
{

	return (mips64be_make_ins_daddu(rd, rs, 0, insp));
}

#define	MIPS64_INS_LBU_TYPE		0x24
#define	MIPS64_INS_LBU_BASE_SHIFT	21
#define	MIPS64_INS_LBU_RT_SHIFT		16
#define	MIPS64_INS_LBU_OFFSET_MASK	0xffff
int
mips64be_make_ins_lbu(u_int base, u_int rt, u_int offset, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((offset & ~MIPS64_INS_LBU_OFFSET_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_LBU_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_LBU_BASE_SHIFT;
	v |= rt << MIPS64_INS_LBU_RT_SHIFT;
	v |= offset;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_LHU_TYPE		0x25
#define	MIPS64_INS_LHU_BASE_SHIFT	21
#define	MIPS64_INS_LHU_RT_SHIFT		16
#define	MIPS64_INS_LHU_OFFSET_MASK	0xffff
int
mips64be_make_ins_lhu(u_int base, u_int rt, u_int offset, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((offset & ~MIPS64_INS_LHU_OFFSET_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_LHU_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_LHU_BASE_SHIFT;
	v |= rt << MIPS64_INS_LHU_RT_SHIFT;
	v |= offset;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_LWU_TYPE		0x27
#define	MIPS64_INS_LWU_BASE_SHIFT	21
#define	MIPS64_INS_LWU_RT_SHIFT		16
#define	MIPS64_INS_LWU_OFFSET_MASK	0xffff
int
mips64be_make_ins_lwu(u_int base, u_int rt, u_int offset, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((offset & ~MIPS64_INS_LWU_OFFSET_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_LWU_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_LWU_BASE_SHIFT;
	v |= rt << MIPS64_INS_LWU_RT_SHIFT;
	v |= offset;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_LD_TYPE		0x37
#define	MIPS64_INS_LD_BASE_SHIFT	21
#define	MIPS64_INS_LD_RT_SHIFT		16
#define	MIPS64_INS_LD_OFFSET_MASK	0xffff
int
mips64be_make_ins_ld(u_int base, u_int rt, u_int offset, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((offset & ~MIPS64_INS_LD_OFFSET_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_LD_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_LD_BASE_SHIFT;
	v |= rt << MIPS64_INS_LD_RT_SHIFT;
	v |= offset;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_DMFC0_TYPE		0x10
#define	MIPS64_INS_DMFC0_DMF		0x1
#define	MIPS64_INS_DMFC0_DMF_SHIFT	21
#define	MIPS64_INS_DMFC0_RT_SHIFT	16
#define	MIPS64_INS_DMFC0_RD_SHIFT	11
int
mips64be_make_ins_dmfc0(u_int rt, u_int rd, uint32_t *insp)
{
	uint32_t v;

	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rd & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	v = MIPS64_INS_DMFC0_TYPE << MIPS64_TYPE_SHIFT;
	v |= MIPS64_INS_DMFC0_DMF << MIPS64_INS_DMFC0_DMF_SHIFT;
	v |= rt << MIPS64_INS_DMFC0_RT_SHIFT;
	v |= rd << MIPS64_INS_DMFC0_RD_SHIFT;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_DMFC2_TYPE		0x12
#define	MIPS64_INS_DMFC2_MF			0x0
#define	MIPS64_INS_DMFC2_MF_SHIFT	21
#define	MIPS64_INS_DMFC2_RT_SHIFT	16
#define	MIPS64_INS_DMFC2_RD_SHIFT	11
#define MIPS64_INS_DMFC2_MASK_SEL	0x7
int
mips64be_make_ins_dmfc2(u_int rt, u_int rd, u_int sel, uint32_t *insp)
{
	uint32_t v;

	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rd & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((sel & ~MIPS64_INS_DMFC2_MASK_SEL) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	v = MIPS64_INS_DMFC2_TYPE << MIPS64_TYPE_SHIFT;
	v |= MIPS64_INS_DMFC2_MF << MIPS64_INS_DMFC2_MF_SHIFT;
	v |= rt << MIPS64_INS_DMFC2_RT_SHIFT;
	v |= rd << MIPS64_INS_DMFC2_RD_SHIFT;
	v |= sel;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_CJR_TYPE		0x12
#define	MIPS64_INS_CJR			0x08
#define	MIPS64_INS_CJR_SHIFT	21
#define	MIPS64_INS_CJR_CB_SHIFT	11
#define	MIPS64_INS_CJR_RT_SHIFT	6
int
mips64be_make_ins_cjr(u_int cb, u_int rt, uint32_t *insp)
{
	uint32_t v;

	if ((cb & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	v = MIPS64_INS_CJR_TYPE << MIPS64_TYPE_SHIFT;
	v |= MIPS64_INS_CJR << MIPS64_INS_CJR_SHIFT;
	v |= cb << MIPS64_INS_CJR_CB_SHIFT;
	v |= rt << MIPS64_INS_CJR_RT_SHIFT;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_CJALR_TYPE		0x12
#define	MIPS64_INS_CJALR			0x07
#define	MIPS64_INS_CJALR_SHIFT		21
#define	MIPS64_INS_CJALR_CB_SHIFT	11
#define	MIPS64_INS_CJALR_RT_SHIFT	6
int
mips64be_make_ins_cjalr(u_int cb, u_int rt, uint32_t *insp)
{
	uint32_t v;

	if ((cb & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	v = MIPS64_INS_CJALR_TYPE << MIPS64_TYPE_SHIFT;
	v |= MIPS64_INS_CJALR << MIPS64_INS_CJALR_SHIFT;
	v |= cb << MIPS64_INS_CJALR_CB_SHIFT;
	v |= rt << MIPS64_INS_CJALR_RT_SHIFT;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_NOP			0
int
mips64be_make_ins_nop(uint32_t *insp)
{

	*insp = MIPS64_NOP;
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_SB_TYPE		0x28
#define	MIPS64_INS_SB_BASE_SHIFT	21
#define	MIPS64_INS_SB_RT_SHIFT		16
#define	MIPS64_INS_SB_OFFSET_MASK	0xffff
int
mips64be_make_ins_sb(u_int base, u_int rt, u_int offset, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((offset & ~MIPS64_INS_SB_OFFSET_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_SB_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_SB_BASE_SHIFT;
	v |= rt << MIPS64_INS_SB_RT_SHIFT;
	v |= offset;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_SD_TYPE		    0x3f
#define	MIPS64_INS_SD_BASE_SHIFT	21
#define	MIPS64_INS_SD_RT_SHIFT		16
#define	MIPS64_INS_SD_OFFSET_MASK	0xffff
int
mips64be_make_ins_sd(u_int base, u_int rt, u_int offset, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((offset & ~MIPS64_INS_SD_OFFSET_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_SD_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_SD_BASE_SHIFT;
	v |= rt << MIPS64_INS_SD_RT_SHIFT;
	v |= offset;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_SH_TYPE		0x29
#define	MIPS64_INS_SH_BASE_SHIFT	21
#define	MIPS64_INS_SH_RT_SHIFT		16
#define	MIPS64_INS_SH_OFFSET_MASK	0xffff
int
mips64be_make_ins_sh(u_int base, u_int rt, u_int offset, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((offset & ~MIPS64_INS_SH_OFFSET_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_SH_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_SH_BASE_SHIFT;
	v |= rt << MIPS64_INS_SH_RT_SHIFT;
	v |= offset;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_SW_TYPE		0x2b
#define	MIPS64_INS_SW_BASE_SHIFT	21
#define	MIPS64_INS_SW_RT_SHIFT		16
#define	MIPS64_INS_SW_OFFSET_MASK	0xffff
int
mips64be_make_ins_sw(u_int base, u_int rt, u_int offset, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((rt & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((offset & ~MIPS64_INS_SW_OFFSET_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_SW_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_SW_BASE_SHIFT;
	v |= rt << MIPS64_INS_SW_RT_SHIFT;
	v |= offset;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

#define	MIPS64_INS_CACHE_TYPE		0x2f
#define	MIPS64_INS_CACHE_BASE_SHIFT	21
#define	MIPS64_INS_CACHE_OP_SHIFT		16
#define	MIPS64_INS_CACHE_OP_INVALIDATE_INS_CACHE_LINE		0x00
#define	MIPS64_INS_CACHE_INDEX_MASK	0xffff
int
mips64be_make_ins_cache_invalidate(u_int base, u_int index, uint32_t *insp)
{
	uint32_t v;

	if ((base & ~MIPS64_MASK_REG) != 0)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if ((index & ~MIPS64_INS_CACHE_INDEX_MASK) != 0)
		return (BERI_DEBUG_ERROR_IMMBOUND);
	v = MIPS64_INS_CACHE_TYPE << MIPS64_TYPE_SHIFT;
	v |= base << MIPS64_INS_CACHE_BASE_SHIFT;
	v |= MIPS64_INS_CACHE_OP_INVALIDATE_INS_CACHE_LINE <<
	    MIPS64_INS_CACHE_OP_SHIFT;
	v |= index;
	*insp = htobe32(v);
	return (BERI_DEBUG_SUCCESS);
}

static void
copyOver(void *buf, size_t* curPos, size_t maxPos, void* p, size_t sz) {
	size_t size = maxPos - (*curPos);

	if (sz < size)
		size = sz;
	
	memcpy(buf+(*curPos), p, size);
	(*curPos) += size;
}

/*
 * The following functions are C wrappers around specific debugging
 * instructions.
 */
int
beri_debug_client_breakpoint_set(struct beri_debug *bdp, u_int bp,
    uint64_t addr)
{
	int ret;
	uint8_t command;
	unsigned char bpc;
	char buffer[32];
	size_t len;
	
	/*
	 * XXX: Gratutious BERI/BERI2 difference.
	 * XXX: rmn30 consider endianness of bp and addr
	 * BERI2 has a single breakpoint command and send the number as
	 * a byte.  BERI has a command for each number...
	 */
	if (bdp->bd_flags & BERI_BERI2) {
		bpc = bp;
		len = 0;

		if (bp > 3)
			return (BERI_DEBUG_ERROR_BPBOUND);

		copyOver(buffer, &len, sizeof(buffer), &bpc,  sizeof(bpc));
		copyOver(buffer, &len, sizeof(buffer), &addr, sizeof(addr));
		ret = beri_debug_client_packet_write(bdp, 
		    BERI2_DEBUG_OP_SETBREAKPOINT, buffer, len);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		return (beri_debug_client_packet_read(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETBREAKPOINT), NULL,
		    0));
	}
	/*
	 * NB: client-side checking as the protocol currently cannot
	 * represent arbitrary numbers of breakpoints, rejecting out-of-bounds
	 * requests by itself.
	 */
	switch (bp) {
	case 0:
		command = BERI_DEBUG_OP_LOAD_BREAKPOINT_0;
		break;

	case 1:
		command = BERI_DEBUG_OP_LOAD_BREAKPOINT_1;
		break;

	case 2:
		command = BERI_DEBUG_OP_LOAD_BREAKPOINT_2;
		break;

	case 3:
		command = BERI_DEBUG_OP_LOAD_BREAKPOINT_3;
		break;

	default:
		return (BERI_DEBUG_ERROR_BPBOUND);
	}
	ret = beri_debug_client_packet_write(bdp, command, &addr,
	    sizeof(addr));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0));
}

int
beri_debug_client_breakpoint_clear(struct beri_debug *bdp, u_int bp)
{

	return (beri_debug_client_breakpoint_set(bdp, bp,
	    BERI_DEBUG_BREAKPOINT_DISABLED));
}

int
beri_debug_client_breakpoint_check(struct beri_debug *bdp, uint64_t *addrp)
{

	if (!(bdp->bd_breakpoint_fired))
		return (BERI_DEBUG_ERROR_NOBREAK);
	*addrp = bdp->bd_breakpoint_addr;
	bdp->bd_breakpoint_fired = 0;
	return (BERI_DEBUG_SUCCESS);
}

/*
 * Block indefinitely awaiting a breakpoint firing.
 */
int
beri_debug_client_breakpoint_wait(struct beri_debug *bdp, uint64_t *addrp)
{
	int ret;
	uint8_t buf[9];

	ret = beri_debug_client_breakpoint_check(bdp, addrp);
	if (ret == BERI_DEBUG_SUCCESS)
		return (ret);
	assert(ret == BERI_DEBUG_ERROR_NOBREAK);
	if (bdp->bd_flags & BERI_BERI2) {
		/* BERI2 returns address + bp number */
		ret = beri_debug_client_packet_read(bdp,
			BERI2_DEBUG_EV_BREAKPOINT_FIRED,
			buf, sizeof(buf));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		*addrp = btoh64(bdp, *((uint64_t *)buf));
		return (BERI_DEBUG_SUCCESS);
	} else
	  return beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_EV_BREAKPOINT_FIRED, addrp, sizeof(*addrp));
}


char*
beri2_state2str(uint8_t state)
{
	switch(state) {
	case BERI2_DEBUG_STATE_PAUSED:
		return "paused";
	case BERI2_DEBUG_STATE_RUNPIPELINED:
		return "running";
	case BERI2_DEBUG_STATE_RUNUNPIPELINED:
		return "running unpipelined";
	case BERI2_DEBUG_STATE_RUNSTREAMING:
		return "streaming mode";
	default:
		return "unknown";
	}
}

void
beri2_print_pipeline_state(struct beri_debug *bdp, uint8_t state)
{
	if (bdp->bd_flags & BERI_BERI2 && !quietflag)
		printf("pipeline state: %s\n", beri2_state2str(state));
}

int
beri_debug_client_get_pipeline_state(struct beri_debug *bdp)
{

	return (bdp->bd_pipeline_state);
}

int
beri_debug_client_set_pipeline_state(struct beri_debug *bdp, uint8_t state,
    uint8_t *oldstatep)
{
	int ret;
	uint8_t command;
	uint8_t oldstate;

	/*
	 * NOP on BERI so we can call unconditionally.
	 */
	if (!(bdp->bd_flags & BERI_BERI2))
		return (BERI_DEBUG_SUCCESS);

	if (bdp->bd_pipeline_state == state) {
		if (oldstatep != NULL)
			*oldstatep = state;
		return (BERI_DEBUG_SUCCESS);
	}

	switch(state) {
	case BERI2_DEBUG_STATE_PAUSED:
		command = BERI2_DEBUG_OP_PAUSEPIPELINE;
		break;
	case BERI2_DEBUG_STATE_RUNPIPELINED:
		command = BERI2_DEBUG_OP_RESUMEPIPELINE;
		break;
	case BERI2_DEBUG_STATE_RUNUNPIPELINED:
		command = BERI2_DEBUG_OP_RESUMEUNPIPELINED;
		break;
	case BERI2_DEBUG_STATE_RUNSTREAMING:
		command = BERI2_DEBUG_OP_RESUMESTREAMING;
		break;
	default:
		return (BERI_DEBUG_USAGE_ERROR);
	}

	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	
	ret = beri_debug_client_packet_read(bdp, BERI2_DEBUG_REPLY(command), 
	     &oldstate, sizeof(oldstate));
	if (ret != BERI_DEBUG_SUCCESS)
	 	return (ret);
	if (oldstatep != NULL)
		*oldstatep=oldstate;
	bdp->bd_pipeline_state = state;
	return (ret);
}

int
beri_debug_client_pause_pipeline(struct beri_debug *bdp, uint8_t *oldstate)
{

	return (beri_debug_client_set_pipeline_state(bdp,
	    BERI2_DEBUG_STATE_PAUSED, oldstate));
}

int
beri_debug_client_resume_pipeline(struct beri_debug *bdp, uint8_t *oldstate)
{

	return (beri_debug_client_set_pipeline_state(bdp,
	    BERI2_DEBUG_STATE_RUNPIPELINED, oldstate));
}

int
beri_debug_client_resume_unpipelined(struct beri_debug *bdp,
    uint8_t *oldstate)
{

	return (beri_debug_client_set_pipeline_state(bdp,
	    BERI2_DEBUG_STATE_RUNUNPIPELINED, oldstate));
}

int
beri_debug_client_load_instruction(struct beri_debug *bdp, uint32_t ins)
{
	int ret;
	uint8_t command;

	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, &ins,
	    sizeof(ins));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0));
}

int
beri_debug_client_load_operand_a(struct beri_debug *bdp, uint64_t v)
{
	int ret;
	uint8_t command;

	/* XXX BERI2: make this a NOP for now */
	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_SUCCESS);

	command = BERI_DEBUG_OP_LOAD_OPERAND_A;
	ret = beri_debug_client_packet_write(bdp, command, &v, sizeof(v));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0));
}

int
beri_debug_client_load_operand_b(struct beri_debug *bdp, uint64_t v)
{
	int ret;
	uint8_t command;

	/* XXX BERI2: make this a NOP for now */
	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_SUCCESS);

	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	ret = beri_debug_client_packet_write(bdp, command, &v, sizeof(v));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0));
}

int
beri_debug_client_execute_instruction(struct beri_debug *bdp,
    uint8_t *excodep)
{
	int ret;
	uint8_t command;

	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read_excode(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0, excodep));
}

int
beri_debug_client_move_pc_to_destination(struct beri_debug *bdp)
{

	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	return (beri_debug_client_packet_simple(bdp,
	    BERI_DEBUG_OP_MOVE_PC_TO_DESTINATION));
}

int
beri_debug_client_report_destination(struct beri_debug *bdp, uint64_t *vp)
{
	int ret;
	uint8_t command;

	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	command = BERI_DEBUG_OP_REPORT_DESTINATION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), vp, sizeof(*vp)));
}

int
beri_debug_client_pause_execution(struct beri_debug *bdp)
{
	int ret;
	uint8_t command;
	uint8_t paused;
	uint8_t *pp = &paused;

	if (bdp->bd_flags & BERI_NO_PAUSE_RESUME)
		return (BERI_DEBUG_SUCCESS);

	if (bdp->bd_flags & BERI_BERI2)
		return (beri_debug_client_pause_pipeline(bdp, NULL));

	command = BERI_DEBUG_OP_PAUSE_EXECUTION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), pp, sizeof(*pp)));
}

int
beri_debug_client_unpipeline_execution(struct beri_debug *bdp)
{
	int ret;
	uint8_t command;
	uint8_t unpipelined;
	uint8_t *up = &unpipelined;

	if (bdp->bd_flags & BERI_BERI2)
		return (beri_debug_client_resume_unpipelined(bdp, NULL));

	command = BERI_DEBUG_OP_UNPIPELINE_EXECUTION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), up, sizeof(*up)));
}

int
beri_debug_client_resume_execution(struct beri_debug *bdp)
{

	if (bdp->bd_flags & BERI_NO_PAUSE_RESUME)
		return (BERI_DEBUG_SUCCESS);

	if (bdp->bd_flags & BERI_BERI2)
		return (beri_debug_client_resume_pipeline(bdp, NULL));

	return (beri_debug_client_packet_simple(bdp,
		BERI_DEBUG_OP_RESUME_EXECUTION));
}

int
beri_debug_client_reset(struct beri_debug *bdp)
{
	int ret;

	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = beri_debug_client_packet_write(bdp, BERI_DEBUG_OP_RESET, NULL,
	    0);
	sleep(1);
	return (ret);
}

int
beri_debug_client_step_execution(struct beri_debug *bdp)
{
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);
	
		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_EXECUTESINGLEINST, NULL, 0);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_EXECUTESINGLEINST),
		    NULL, 0));
	}
	return (beri_debug_client_packet_simple(bdp,
	    BERI_DEBUG_OP_STEP_EXECUTION));
}

/*
 * The following functions are wrappers around multiple debugging
 * instructions, and perform high-level (and useful) actions common in
 * debuggers.
 */
int
beri_debug_client_get_reg(struct beri_debug *bdp, u_int regnum,
    uint64_t *vp)
{
	uint32_t ins;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		ret = beri_debug_client_get_reg_pipelined_send(bdp, regnum);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		return (beri_debug_client_get_reg_pipelined_response(bdp, vp));
	}

	/*
	 * Construct and execute a MIPS instruction to move the register of
	 * interest into the destination register.  No exception is ever
	 * expected here, so an exception code is not returnable to the
	 * caller.
	 */
	ret = mips64be_make_ins_move(BERI_DEBUG_REGNUM_DESTINATION, regnum,
	    &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_execute_instruction(bdp, NULL);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Retrieve the resulting value.
	 */
	return (beri_debug_client_report_destination(bdp, vp));
}

int
beri_debug_client_get_reg_pipelined_send(struct beri_debug *bdp,
    u_int regnum)
{
	uint32_t ins;
	uint8_t command, reg;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		reg = regnum;

		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		return (beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_GETREGISTER, &reg, sizeof(reg)));
	}
	/*
	 * Construct and execute a MIPS instruction to move the register of
	 * interest into the destination register.  Response is caught by
	 * beri_debug_client_get_reg_pipelined_response.
	 */
	/* Build Instruction */
	ret = mips64be_make_ins_move(BERI_DEBUG_REGNUM_DESTINATION,
	    regnum, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Instruction Send */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, &ins,
	    sizeof(ins));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction Send */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Report Destination Send */
	command = BERI_DEBUG_OP_REPORT_DESTINATION;
	return (beri_debug_client_packet_write(bdp, command, NULL, 0));
}

int
beri_debug_client_get_reg_pipelined_response(struct beri_debug *bdp,
    uint64_t *vp)
{
	uint8_t command;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		return (beri_debug_client_packet_read(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_GETREGISTER), vp,
		    sizeof(*vp)));
	}

	/*
	 * Catch the response of a register read.  No exception is ever
	 * expected here, so an exception code is not returnable to the
	 * caller.
	 */
	/* Instruction Response */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction Response */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = (beri_debug_client_packet_read_excode(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0, NULL));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Report Destination Response */
	command = BERI_DEBUG_OP_REPORT_DESTINATION;
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), vp, sizeof(*vp)));
}

int
beri_debug_client_get_pc(struct beri_debug *bdp, uint64_t *addrp)
{
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);
		
		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_GETPC, NULL, 0);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		ret = beri_debug_client_packet_read(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_GETPC), addrp,
		    sizeof(*addrp));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
	}
	else {
		/*
		 * Pull PC into the destination register, then retrieve resulting
		 * value.
		 */
		ret = beri_debug_client_move_pc_to_destination(bdp);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		ret = beri_debug_client_report_destination(bdp, addrp);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
	}
	return BERI_DEBUG_SUCCESS;
}

int
beri_debug_client_get_c0reg(struct beri_debug *bdp, u_int regnum,
    uint64_t *vp)
{
	uint32_t ins;
	int ret;

	/* XXX BERI2 */
	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	/*
	 * Construct and execute a MIPS instruction to move the CP0 register
	 * of interest into the destination register.
	 *
	 * XXXRW: It seems likely that in the current world order, exceptions
	 * can be returned when dmfc0 is executed by the debug unit.  In the
	 * future we don't think this will be the case, so this API cannot
	 * return one.  We might need to change this.
	 */
	ret = mips64be_make_ins_dmfc0(BERI_DEBUG_REGNUM_DESTINATION, regnum,
	    &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_execute_instruction(bdp, NULL);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Retrieve the resulting value.
	 */
	return (beri_debug_client_report_destination(bdp, vp));
}

int
beri_debug_client_get_c0reg_pipelined_send(struct beri_debug *bdp,
    u_int regnum)
{
	uint32_t ins;
	uint8_t command;
	int ret;

	/* XXX BERI2 */
	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	/*
	 * Construct and execute a MIPS instruction to move the CP0 register
	 * of interest into the destination register.  Response is caught by
	 * beri_debug_client_get_reg_pipelined_response.
	 */
	/* Build Instruction */
	ret = mips64be_make_ins_dmfc0(BERI_DEBUG_REGNUM_DESTINATION, regnum,
	    &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Instruction Send */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, &ins,
	    sizeof(ins));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction Send */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Report Destination Send */
	command = BERI_DEBUG_OP_REPORT_DESTINATION;
	return (beri_debug_client_packet_write(bdp, command, NULL, 0));
}

int
cheri_debug_client_get_c2reg_field(struct beri_debug *bdp, uint8_t regnum, uint8_t field, uint64_t *valp) {
	int ret;
	uint32_t ins;
	uint64_t val;
	uint8_t command;
	uint8_t excode;
	
	/*
	 * Construct and execute a MIPS to move the CP2 register
	 * of interest into the destination register.
	 */
	/* Build Instruction */
	ret = mips64be_make_ins_dmfc2(BERI_DEBUG_REGNUM_DESTINATION, regnum,
	    field, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Instruction Send */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, &ins,
	    sizeof(ins));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction Send */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Report Destination Send */
	command = BERI_DEBUG_OP_REPORT_DESTINATION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	
	/* Get Responses */
	/* Instruction Response */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction Response*/
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = beri_debug_client_packet_read_excode(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0, &excode);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction Response*/
	command = BERI_DEBUG_OP_REPORT_DESTINATION;
	ret = beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), &val, sizeof(val));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
		
	*valp = btoh64(bdp, val);
	return BERI_DEBUG_SUCCESS;
}

int
cheri_debug_client_get_c2reg(struct beri_debug *bdp, uint8_t regnum, struct cap *cap) {
	int ret;
	uint64_t val;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_GETC2REGISTER, &regnum, sizeof(regnum));

		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_GETC2REGISTER), cap, sizeof(*cap)));
	}

	ret = cheri_debug_client_get_c2reg_field(bdp, regnum, CHERI_DEBUG_CAP_BASE, &val);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	cap->base = val;

	ret = cheri_debug_client_get_c2reg_field(bdp, regnum, CHERI_DEBUG_CAP_LENGTH, &val);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	cap->length = val;

	ret = cheri_debug_client_get_c2reg_field(bdp, regnum, CHERI_DEBUG_CAP_TYPE, &val);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	cap->type = val;

	ret = cheri_debug_client_get_c2reg_field(bdp, regnum, CHERI_DEBUG_CAP_PERMISSIONS, &val);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	cap->perms = val;

	ret = cheri_debug_client_get_c2reg_field(bdp, regnum, CHERI_DEBUG_CAP_UNSEALED, &val);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	cap->unsealed = val;

	ret = cheri_debug_client_get_c2reg_field(bdp, regnum, CHERI_DEBUG_CAP_TAG, &val);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	cap->tag = val;

	return (BERI_DEBUG_SUCCESS);
}

int
cheri_debug_client_pcc_to_cr26(struct beri_debug *bdp)
{
	uint32_t ins;
	int ret;

	/* XXX BERI2: we do not implement this yet... */
	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_SUCCESS);

	/*
	 * Construct and execute a MIPS instruction to move the program
	 * counter capability register (PCC) to capability register 26
	 * (CJALR), and then jump back to capability register 26.  The result
	 * is that we have the same PC and PCC, but PCC is now stored in
	 * capability register 26 so that we can inspect it.
	 *
	 * XXX: This is a destructive operation.
	 *
	 * This operation requires pausing the pipeline due to the jumps.
	 */
	ret = beri_debug_client_pause_execution(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Load zeros into the operands to ensure that we jump to offset zero
	 * and then construct, load and execute a cjalr instruction.
	 */
	ret = beri_debug_client_load_operand_a(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_cjalr(0, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_execute_instruction(bdp, NULL);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Construct, load and execute a cjr back to the original capability.
	 */
	ret = mips64be_make_ins_cjr(CHERI_DEBUG_CAPABILITY_LINK_REG, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_execute_instruction(bdp, NULL));
}

int
cheri_debug_client_get_c2reg_pipelined_send(struct beri_debug *bdp,
    u_int regnum, u_int field)
{
	uint32_t ins;
	uint8_t command;
	int ret;

	/* XXX BERI2 */
	if (bdp->bd_flags & BERI_BERI2)
		return BERI_DEBUG_USAGE_ERROR;

	/*
	 * Construct and execute a MIPS instruction to move the CP2 register
	 * of interest into the destination register.  Response is caught by
	 * beri_debug_client_get_reg_pipelined_response.
	 */
	/* Build Instruction */
	ret = mips64be_make_ins_dmfc2(BERI_DEBUG_REGNUM_DESTINATION, regnum,
	    field, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Instruction Send */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, &ins,
	    sizeof(ins));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction Send */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Report Destination Send */
	command = BERI_DEBUG_OP_REPORT_DESTINATION;
	return (beri_debug_client_packet_write(bdp, command, NULL, 0));
}

int
beri_debug_client_lbu(struct beri_debug *bdp, uint64_t addr, uint8_t *vp,
    uint8_t *excodep)
{
	uint64_t v;
	uint32_t ins;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_GETBYTE, &addr, sizeof(addr));

		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_GETBYTE), vp,
		    sizeof(*vp), excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to load a byte into the
	 * destination register.  This requires first setting up the base
	 * address via an operand register.  The possibility of an exception
	 * being returned to the caller is allowed for in this API.
	 *
	 * XXXRW: How should we know which operand register to use -- will it
	 * remin static for the lifetime of this library?
	 *
	 * XXXRW: I'm also setting operand B to 0 -- is this necessary?
	 */
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_lbu(BERI_DEBUG_REGNUM_DESTINATION,
	    BERI_DEBUG_REGNUM_DESTINATION, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_execute_instruction(bdp, excodep);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_report_destination(bdp, &v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Before truncating the returned 64-bit value to 8 bits for the
	 * caller, we must convert to host byte order.  Simply casting would
	 * remove the wrong byte.
	 *
	 * XXXRW: Embedded knowledge of remote CPU endianness.
	 */
	*vp = btoh64(bdp, v) & 0xff;
	return (BERI_DEBUG_SUCCESS);
}

int
beri_debug_client_lhu(struct beri_debug *bdp, uint64_t addr, uint16_t *vp,
    uint8_t *excodep)
{
	uint64_t v;
	uint32_t ins;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_GETHALFWORD, &addr, sizeof(addr));

		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_GETHALFWORD), vp,
		    sizeof(*vp), excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to load a half word into
	 * the destination register.  This requires first setting up the base
	 * address via an operand register.  The possibility of an exception
	 * being returned to the caller is allowed for in this API.
	 */
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_lhu(BERI_DEBUG_REGNUM_DESTINATION,
	    BERI_DEBUG_REGNUM_DESTINATION, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_execute_instruction(bdp, excodep);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_report_destination(bdp, &v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Before truncating the returned 64-bit value to 16 bits for the
	 * caller, we must convert to host byte order.  Simply casting would
	 * remove the wrong byte.
	 *
	 * XXXRW: Embedded knowledge of remote CPU endianness.
	 */
	*vp = btoh64(bdp, v) & 0xffff;
	return (BERI_DEBUG_SUCCESS);
}

int
beri_debug_client_lwu(struct beri_debug *bdp, uint64_t addr, uint32_t *vp,
    uint8_t *excodep)
{
	uint64_t v;
	uint32_t ins;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_GETWORD, &addr, sizeof(addr));

		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_GETWORD), vp,
		    sizeof(*vp), excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to load a half word into
	 * the destination register.  This requires first setting up the base
	 * address via an operand register.  The possibility of an exception
	 * being returned to the caller is allowed for in this API.
	 *
	 */
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_lwu(BERI_DEBUG_REGNUM_DESTINATION,
	    BERI_DEBUG_REGNUM_DESTINATION, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_execute_instruction(bdp, excodep);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_report_destination(bdp, &v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Before truncating the returned 64-bit value to 32 bits for the
	 * caller, we must convert to host byte order.  Simply casting would
	 * remove the wrong byte.
	 *
	 * XXXRW: Embedded knowledge of remote CPU endianness.
	 */
	*vp = btoh64(bdp, v) & 0xffffffff;
	return (BERI_DEBUG_SUCCESS);
}

int
beri_debug_client_ld(struct beri_debug *bdp, uint64_t addr, uint64_t *vp,
    uint8_t *excodep)
{
	uint32_t ins;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);
		
		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_GETDOUBLEWORD, &addr, sizeof(addr));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_GETDOUBLEWORD), vp,
		    sizeof(*vp), excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to load a double word into
	 * the destination register.  This requires first setting up the base
	 * address via an operand register.  The possibility of an exception
	 * being returned to the caller is allowed for in this API.
	 *
	 * XXXRW: How should we know which operand register to use -- will it
	 * remin static for the lifetime of this library?
	 *
	 * XXXRW: I'm also setting operand B to 0 -- is this necessary?
	 */
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_ld(BERI_DEBUG_REGNUM_DESTINATION,
	    BERI_DEBUG_REGNUM_DESTINATION, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_execute_instruction(bdp, excodep);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_report_destination(bdp, vp));
}

int
beri_debug_client_sb(struct beri_debug *bdp, uint64_t addr, uint8_t v,
    uint8_t *excodep)
{
	uint32_t ins;
	int ret;
	char buffer[32];
	size_t len;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);
		
		len = 0;
		copyOver(buffer, &len, sizeof(buffer), &v, sizeof(v));
		copyOver(buffer, &len, sizeof(buffer), &addr, sizeof(addr));

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_SETBYTE, buffer, len);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETBYTE), NULL, 0,
		    excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to store a double word
	 * into an arbitrary memory location.
	 *
	 * XXXRW: Endian-aware to generate 64-bit register value from byte.
	 */
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, htobe64(v));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_sb(BERI_DEBUG_REGNUM_DONTCARE,
	    BERI_DEBUG_REGNUM_DONTCARE, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_execute_instruction(bdp, excodep));
}

int
beri_debug_client_sh(struct beri_debug *bdp, uint64_t addr, uint16_t v,
    uint8_t *excodep)
{
	uint32_t ins;
	int ret;
	char buffer[32];
	size_t len;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);
		
		len = 0;
		copyOver(buffer, &len, sizeof(buffer), &v, sizeof(v));
		copyOver(buffer, &len, sizeof(buffer), &addr, sizeof(addr));

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_SETHALFWORD, buffer, len);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETHALFWORD), NULL, 0,
		    excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to store a half-word into
	 * an arbitrary memory location.  We specify the address and data
	 * using debug unit operands.
	 */
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, htobe64(v));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_sh(BERI_DEBUG_REGNUM_DONTCARE,
	    BERI_DEBUG_REGNUM_DONTCARE, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_execute_instruction(bdp, excodep));
}

int
beri_debug_client_sw(struct beri_debug *bdp, uint64_t addr, uint32_t v,
    uint8_t *excodep)
{
	uint32_t ins;
	int ret;
	char buffer[32];
	size_t len;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);
		
		len = 0;
		copyOver(buffer, &len, sizeof(buffer), &v, sizeof(v));
		copyOver(buffer, &len, sizeof(buffer), &addr, sizeof(addr));

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_SETWORD, buffer, len);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETWORD), NULL, 0,
		    excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to store a word into an
	 * arbitrary memory location.  We specify the address and data using
	 * debug unit operands.
	 */
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, htobe64(v));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_sw(BERI_DEBUG_REGNUM_DONTCARE,
	    BERI_DEBUG_REGNUM_DONTCARE, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_execute_instruction(bdp, excodep));
}

int
beri_debug_client_sd(struct beri_debug *bdp, uint64_t addr, uint64_t v,
    uint8_t *excodep)
{
	uint32_t ins;
	int ret;
	char buffer[32];
	size_t len;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);
		
		len = 0;
		copyOver(buffer, &len, sizeof(buffer), &v, sizeof(v));
		copyOver(buffer, &len, sizeof(buffer), &addr, sizeof(addr));

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_SETDOUBLEWORD, buffer, len);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);

		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETDOUBLEWORD),
		    NULL, 0, excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to store a double word
	 * into an arbitrary memory location.  Register numbers in the store
	 * instruction are ignored; instead, we specify the address and data
	 * using debug unit operands.
	 *
	 * XXXRW: As with ld, the operand configuration is under-specified.
	 */
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = mips64be_make_ins_sd(BERI_DEBUG_REGNUM_DONTCARE,
	    BERI_DEBUG_REGNUM_DONTCARE, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_execute_instruction(bdp, excodep));
}

int
beri_debug_client_sd_pipelined_send(struct beri_debug *bdp, uint64_t addr,
    uint64_t v)
{
	uint32_t ins;
	uint8_t command;
	int ret;
	char buffer[32];
	size_t len;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		len = 0;
		copyOver(buffer, &len, sizeof(buffer), &v, sizeof(v));
		copyOver(buffer, &len, sizeof(buffer), &addr, sizeof(addr));

		return (beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_SETDOUBLEWORD, buffer, len));
	}

	/*
	 * Construct and execute a MIPS instruction to store a double word
	 * into an arbitrary memory location.  Register numbers in the store
	 * instruction are ignored; instead, we specify the address and data
	 * using debug unit operands.
	 *
	 * XXXRW: As with ld, the operand configuration is under-specified.
	 */

	/* Operand A Send */
	command = BERI_DEBUG_OP_LOAD_OPERAND_A;
	ret = beri_debug_client_packet_write(bdp, command, &addr,
	    sizeof(addr));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Operand B Send */
	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	ret = beri_debug_client_packet_write(bdp, command, &v, sizeof(v));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Instruction Send */
	ret = mips64be_make_ins_sd(BERI_DEBUG_REGNUM_DONTCARE,
	    BERI_DEBUG_REGNUM_DONTCARE, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, &ins,
	    sizeof(ins));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction Send */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	return (beri_debug_client_packet_write(bdp, command, NULL, 0));
}

int
beri_debug_client_sd_pipelined_response(struct beri_debug *bdp,
    uint8_t *excodep)
{
	uint8_t command;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETDOUBLEWORD),
		    NULL, 0, excodep));
	}

	/*
	 * Construct and execute a MIPS instruction to store a double word
	 * into an arbitrary memory location.  Register numbers in the store
	 * instruction are ignored; instead, we specify the address and data
	 * using debug unit operands.
	 *
	 * XXXRW: As with ld, the operand configuration is under-specified.
	 */

	/* Operand A Response */
	command = BERI_DEBUG_OP_LOAD_OPERAND_A;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Operand B Response */
	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Instruction Response */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	return (beri_debug_client_packet_read_excode(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0, excodep));
}

#if 0
/* XXX-BD: this code is unused and obviously wrong so it's ifdef'd out */
int
beri_debug_client_sh_pipelined_send(struct beri_debug *bdp, uint64_t addr,
    uint16_t v)
{
	uint32_t ins;
	uint8_t command;
	uint64_t data;
	int ret;
	char buffer[32];
	size_t len;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		len = 0;
		copyOver(buffer, &len, sizeof(buffer), &v, sizeof(v));
		copyOver(buffer, &len, sizeof(buffer), &addr, sizeof(addr));

		return (beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_SETHALFWORD, buffer, len));
	}

	/*
	 * Construct and execute a MIPS instruction to store a half-word into
	 * memory at an arbitrary location.  Register numbers in the store
	 * instruction are ignored; instead, we specify the address and data
	 * using debug unit operands.
	 */

	/* Operand A = Address Send */
	command = BERI_DEBUG_OP_LOAD_OPERAND_A;
	ret = beri_debug_client_packet_write(bdp, command, &addr,
	    sizeof(addr));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Operand B = Write Instruction Send */
	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	data = ISF_WRITE;
	ret = beri_debug_client_packet_write(bdp, command, &data,
	    sizeof(data));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Write Instruction Send */
	ret = mips64be_make_ins_sh(BERI_DEBUG_REGNUM_DONTCARE,
	    BERI_DEBUG_REGNUM_DONTCARE, 0, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, &ins,
	    sizeof(ins));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Write Instruction Send */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Operand B = Write Value Send */
	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	data = v;
	data = (data)|(data<<16)|(data<<32)|(data<<48);
	data = htobe64(data);
	ret = beri_debug_client_packet_write(bdp, command, &data,
	    sizeof(data));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Execute Write Value Send using the same address and instruction
	 * loaded previously.
	 */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	return (beri_debug_client_packet_write(bdp, command, NULL, 0));
}

int
beri_debug_client_sh_pipelined_response(struct beri_debug *bdp,
    uint8_t *excodep)
{
	uint8_t command;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		return (beri_debug_client_packet_read_excode(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETHALFWORD),
		    NULL, 0, excodep));
	}

	/*
	 * Receive the responses generated by the
	 * beri_debug_client_sh_pipelined_send function.
	 */

	/* Operand A Response */
	command = BERI_DEBUG_OP_LOAD_OPERAND_A;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Operand B Response */
	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Instruction Response */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	ret = beri_debug_client_packet_read_excode(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0, excodep);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Operand B Response */
	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	return (beri_debug_client_packet_read_excode(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0, excodep));
}
#endif

int
beri_debug_client_nop_pipelined_send(struct beri_debug *bdp)
{
	uint32_t ins;
	uint8_t command;
	uint64_t data;
	int ret;

	/* XXX BERI2 */
	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	/* Operand A = Address Send */
	command = BERI_DEBUG_OP_LOAD_OPERAND_A;
	data = 0;
	ret = beri_debug_client_packet_write(bdp, command, &data,
	    sizeof(data));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Operand B = Write Instruction Send */
	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	data = 0;
	ret = beri_debug_client_packet_write(bdp, command, &data,
	    sizeof(data));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Write Instruction Send */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ins = 0;
	ret = beri_debug_client_packet_write(bdp, command, &ins,
	    sizeof(ins));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Write Instruction Send */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	return (beri_debug_client_packet_write(bdp, command, NULL, 0));
}

int
beri_debug_client_nop_pipelined_response(struct beri_debug *bdp,
    uint8_t *excodep)
{
	uint8_t command;
	int ret;

	/* XXX BERI2 */
	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	/*
	 * Receive the responses generated by the
	 * beri_debug_nop_pipelined_send function.
	 */

	/* Operand A Response */
	command = BERI_DEBUG_OP_LOAD_OPERAND_A;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Operand B Response */
	command = BERI_DEBUG_OP_LOAD_OPERAND_B;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Instruction Response */
	command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
	ret = (beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    NULL, 0));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	/* Execute Instruction */
	command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
	return (beri_debug_client_packet_read_excode(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0, excodep));
}

int
beri_debug_client_invalidateicache(struct beri_debug *bdp)
{
	uint32_t ins;
	int index;
	int ret;
	uint8_t excodep;
	uint8_t command;

	/* XXX BERI2 */
	if (bdp->bd_flags & BERI_BERI2)
		return(BERI_DEBUG_USAGE_ERROR);

	/*
	 * Construct and execute a MIPS instruction to invalidate a line of
	 * the instruction cache.  This requires first setting up a base of
	 * zero, as we will use the immediate value to choose the cache line.
	 *
	 * XXXRW: I don't know which operand will be used for base, so I set
	 * both to zero.
	 */
	ret = beri_debug_client_load_operand_a(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	for (index = 0; index < 4096; index += 8) {
		ret = mips64be_make_ins_cache_invalidate(0, (index), &ins);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		/* Load the Instruction */
		command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
		ret = beri_debug_client_packet_write(bdp, command, &ins,
		    sizeof(ins));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		/* Execute the Instruction */
		command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
		ret = beri_debug_client_packet_write(bdp, command, NULL, 0);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
	}
	for (index = 0; index < 4096; index += 8) {
		/* Check the Instruction Receipt */
		command = BERI_DEBUG_OP_LOAD_INSTRUCTION;
		ret = beri_debug_client_packet_read(bdp,
		    BERI_DEBUG_REPLY(command), NULL, 0);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		/* Check Instruction Execution */
		command = BERI_DEBUG_OP_EXECUTE_INSTRUCTION;
		ret = beri_debug_client_packet_read_excode(bdp,
		    BERI_DEBUG_REPLY(command), NULL, 0, &excodep);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
	}
	return (BERI_DEBUG_SUCCESS);
}

int
beri_debug_client_set_pc(struct beri_debug *bdp, uint64_t addr)
{
	uint32_t ins;
	int ret;

	if (bdp->bd_flags & BERI_BERI2) {
		/* XXX: could just pause which would be more like BERI */
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
			return (BERI_DEBUG_ERROR_NOTPAUSED);

		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_SETPC, &addr, sizeof(addr));
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		return (beri_debug_client_packet_read(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETPC), NULL, 0));
	}

	/*
	 * Construct and execute a MIPS instruction to jump to the target PC.
	 */

	ret = mips64be_make_ins_jr(BERI_DEBUG_REGNUM_DONTCARE, &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_a(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_execute_instruction(bdp, NULL));
}

int
beri_debug_client_set_thread(struct beri_debug *bdp, uint8_t thread)
{
	int ret;

	if (!(bdp->bd_flags & BERI_BERI2))
		return BERI_DEBUG_USAGE_ERROR;

	ret = beri_debug_client_packet_write(bdp,
		BERI2_DEBUG_OP_SETTHREAD, &thread, sizeof(thread));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
		BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETTHREAD), NULL, 0));
}

int
beri_debug_client_set_reg(struct beri_debug *bdp, u_int regnum, uint64_t v)
{
	uint32_t ins;
	int ret;
	char buffer[32];
	size_t len;

	if (bdp->bd_flags & BERI_BERI2) {
		if (beri_debug_client_get_pipeline_state(bdp) !=
		    BERI2_DEBUG_STATE_PAUSED)
		return (BERI_DEBUG_ERROR_NOTPAUSED);

		len = 0;
		copyOver(buffer, &len, sizeof(buffer), &regnum, 1);
		copyOver(buffer, &len, sizeof(buffer), &v, sizeof(v));
		ret = beri_debug_client_packet_write(bdp,
		    BERI2_DEBUG_OP_SETREGISTER, buffer, len);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		return (beri_debug_client_packet_read(bdp,
		    BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETREGISTER), NULL, 0));
	}

	/*
	 * Construct and execute a MIPS instruction to move one register to
	 * another.  The origin register number is ignored; instead, the value
	 * in an operand register is used as the origin for the operation.
	 *
	 * XXXRW: As with ld, the operand configuration is under-specified.
	 */

	ret = mips64be_make_ins_move(regnum, BERI_DEBUG_REGNUM_DONTCARE,
	    &ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_a(bdp, v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_instruction(bdp, ins);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_execute_instruction(bdp, NULL));
}

int
beri_debug_client_stream_trace_start(struct beri_debug *bdp)
{
	uint8_t command = BERI_DEBUG_OP_STREAM_TRACE_START;
	uint8_t oldstate;
	int     ret;

	if (bdp->bd_flags & BERI_BERI2) {
	  ret = beri_debug_client_packet_write(bdp, BERI2_DEBUG_OP_RESUMESTREAMING, NULL, 0);
	  if (ret != BERI_DEBUG_SUCCESS)
	    return (ret);
	  
	  return beri_debug_client_packet_read(bdp, BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_RESUMESTREAMING), 
					      &oldstate, sizeof(oldstate));
	}


	return (beri_debug_client_packet_write(bdp, command, NULL, 0));
}

int
beri_debug_client_pop_trace_send(struct beri_debug *bdp)
{
	uint8_t command = BERI_DEBUG_OP_POP_TRACE;

	/* XXX BERI2 */
	if (bdp->bd_flags & BERI_BERI2)
		return (BERI_DEBUG_USAGE_ERROR);

	return (beri_debug_client_packet_write(bdp, command, NULL, 0));
}

int
beri_debug_client_pop_trace_receive(struct beri_debug *bdp,
    struct beri_debug_trace_entry *tep)
{
	int ret;
	uint8_t command = BERI_DEBUG_OP_POP_TRACE;
	uint8_t buf[32];

	if (bdp->bd_flags & BERI_BERI2) {
		ret = beri_debug_client_packet_read(bdp, BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_POPTRACE),
						     tep, sizeof(*tep));
		if (ret != BERI_DEBUG_SUCCESS)
			return ret;
		return tep->valid ? BERI_DEBUG_SUCCESS : BERI_DEBUG_USAGE_ERROR;
	}

	ret = beri_debug_client_packet_read(bdp, BERI_DEBUG_REPLY(command),
	    buf, sizeof(buf));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * For some reason the data comes out backwards and confused so we
	 * can't just cast the buffer :-(.
	 */
	//for(ret=0;ret<32;ret++) printf("0x%hhx ", buf[ret]);
	//printf("\n");
	tep->valid = (buf[31] & 0x80) >> 7;
	tep->version = (buf[31] & 0x78) >> 3;
	tep->exception = (buf[31] & 0x07) << 2 | (buf[30] & 0xc0) >> 6;
	tep->cycles = (buf[30] & 0x3F) << 4 | (buf[29] & 0xF0) >> 4;
	tep->asid = (buf[29] & 0x0F) << 4 | (buf[28] & 0xF0) >> 4;
	tep->inst = *((uint32_t *) &buf[24]);
	tep->pc = *((uint64_t *) &buf[16]);
	tep->val1 = *((uint64_t *) &buf[8]);
	tep->val2 = *((uint64_t *) &buf[0]);
	return (BERI_DEBUG_SUCCESS);
}

int
beri_trace_entry_to_vector(struct beri_debug_trace_entry *tep, uint64_t *buf)
{
	int i;
	uint32_t top=0;
	
	for(i=0; i<4; i++) buf[i] = 0;
	top = ((((uint32_t)tep->valid)<<31)     & 0x80000000) | top;
	top = ((((uint32_t)tep->version)<<27)   & 0x78000000) | top;
	top = ((((uint32_t)tep->exception)<<22) & 0x07c00000) | top;
	top = ((((uint32_t)tep->cycles)<<12)    & 0x003FFc00) | top;
	buf[0] = (((uint64_t)htobe32(tep->inst))<<32) | htobe32(top);
	buf[1] = htobe64(tep->pc);
	buf[2] = htobe64(tep->val1);
	buf[3] = htobe64(tep->val2);
	return BERI_DEBUG_SUCCESS;
}

int
beri_trace_filter_set(struct beri_debug *bdp,
    struct beri_debug_trace_entry *tep)
{
	int ret;
	uint8_t command;
	uint64_t buf[4];
	
	if (bdp->bd_flags & BERI_BERI2) {
	  ret = beri_debug_client_packet_write(bdp, BERI2_DEBUG_OP_SETTRACEFILTER, tep, sizeof(*tep));
	  if (ret != BERI_DEBUG_SUCCESS)
	    return ret;
	  ret = beri_debug_client_packet_read(bdp, BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETTRACEFILTER),
					      NULL, 0);
	  return ret;
	}

	ret = beri_trace_entry_to_vector(tep, buf);

	command = BERI_DEBUG_OP_LOAD_TRACE_FILTER;
	ret = beri_debug_client_packet_write(bdp, command, buf, 32);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0));
}

int
beri_trace_filter_mask_set(struct beri_debug *bdp,
    struct beri_debug_trace_entry *tep)
{
	int ret;
	uint8_t command;
	uint64_t buf[4];
	
	if (bdp->bd_flags & BERI_BERI2) {
	  ret = beri_debug_client_packet_write(bdp, BERI2_DEBUG_OP_SETTRACEMASK, tep, sizeof(*tep));
	  if (ret != BERI_DEBUG_SUCCESS)
	    return ret;
	  ret = beri_debug_client_packet_read(bdp, BERI2_DEBUG_REPLY(BERI2_DEBUG_OP_SETTRACEMASK),
					      NULL, 0);
	  return ret;
	}

	ret = beri_trace_entry_to_vector(tep, buf);

	command = BERI_DEBUG_OP_LOAD_TRACE_FILTER_MASK;
	ret = beri_debug_client_packet_write(bdp, command, buf, 32);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (beri_debug_client_packet_read(bdp,
	    BERI_DEBUG_REPLY(command), NULL, 0));
}

/*
 * Host to BERI endian swap.
 */
uint64_t
btoh64(struct beri_debug *bdp, uint64_t v)
{
	if(bdp->bd_flags & BERI_BERI2)
		return le64toh(v);
	else
		return be64toh(v);
}

/*
 * BERI to host endian swap.
 */
uint64_t
htob64(struct beri_debug *bdp, uint64_t v)
{
	if(bdp->bd_flags & BERI_BERI2)
		return htole64(v);
	else
		return htobe64(v);
}

/*
 * Map a physical address into virtual address space.
 */
uint64_t
physical2virtual(struct beri_debug *bdp, uint64_t v)
{
  return v|0x9000000000000000;
}
