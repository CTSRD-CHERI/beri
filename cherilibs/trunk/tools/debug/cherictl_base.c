/*-
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2012-2013 Jonathan Woodruff
 * Copyright (c) 2012-2013 SRI International
 * Copyright (c) 2012 Robert Norton
 * Copyright (c) 2012, 2014-2015 Bjoern A. Zeeb
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2015 Theo Markettos
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
 * Simple BERI debug tool: various debugging operations can be exercised from
 * the command line, including inspecting register state, pausing, resuming,
 * and single-stepping the processor.
 */

/* Required for asprintf definition */
#define	_GNU_SOURCE

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#ifdef BERI_NETFPGA
#include <sys/ioctl.h>
#include <fcntl.h>
#include <string.h>
#ifdef __FreeBSD__
#include <sys/sockio.h>
#endif
#include <net/if.h>
#endif

#ifdef __linux__
#include <endian.h>
#elif __APPLE__
#include "macosx.h"
#else
#include <sys/endian.h>
#endif

#include <assert.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include "../../include/cheri_debug.h"
#ifdef BERI_NETFPGA
#include "berictl_netfpga.h"
#endif
#include "cherictl.h"
#include "mips_decode.h"
#include "status_bar.h"

/* Make up for differences in socket API */
#ifdef	__APPLE__
#define	MSG_NOSIGNAL 0
#endif



#define BERI2_PAUSE(bdp, oldstate) do {					\
	int _ret;							\
	if ((oldstate = beri_debug_client_get_pipeline_state(bdp)) !=	\
	    BERI2_DEBUG_STATE_PAUSED) {				\
		_ret = beri_debug_client_pause_pipeline((bdp),	\
		    &(oldstate));					\
		if (_ret != BERI_DEBUG_SUCCESS)			\
			return (_ret);					\
		beri2_print_pipeline_state(bdp, oldstate);		\
	}								\
} while(0)

#define BERI2_RESUME(bdp, oldstate) do {				\
	int _ret;							\
	if ((oldstate) != BERI2_DEBUG_STATE_PAUSED 			\
		&& (oldstate) != BERI2_DEBUG_STATE_RUNSTREAMING) {	\
		_ret = beri_debug_client_set_pipeline_state((bdp),	\
		    (oldstate), NULL);					\
		/*							\
		 * XXX-library: Print warning to avoid trashing prior	\
		 * error status.					\
		 */							\
		if (_ret != BERI_DEBUG_SUCCESS)			\
			warnx("%s: failed to resume BERI2: %s",		\
			    __func__, beri_debug_strerror(_ret));	\
	}								\
} while(0)

static int keepRunning = 1;

void 
intHandler(int unused) {
    keepRunning = 0;
    printf("You pressed control-C!");
}

int debugflag;
int quietflag;
static pid_t nios2_terminal_pid = 0;
struct termios trm_save;

int
hex2addr(const char *string, uint64_t *addrp)
{
	const char *cp;
	uint64_t addr;
	u_int len;

	cp = string;
	if (strlen(cp) >= 2 && cp[0] == '0' && cp[1] == 'x')
		cp += 2;
	for (addr = 0, len = 0; *cp != '\0' && len < 16; cp++) {
		len++;
		if (len > 17) {
			printf("too long %d\n", len);
			return (BERI_DEBUG_ERROR_ADDR_INVALID);
		}
		addr <<= 4;
		if (*cp >= '0' && *cp <= '9')
			addr |= (*cp - '0');
		else if (*cp >= 'a' && *cp <= 'f')
			addr |= (*cp - 'a') + 10;
		else if (*cp >= 'A' && *cp <= 'F')
			addr |= (*cp - 'A') + 10;
		else
			return (BERI_DEBUG_ERROR_ADDR_INVALID);
	}
	*addrp = addr;
	return (BERI_DEBUG_SUCCESS);
}

int
str2regnum(const char *string, u_int *regnump)
{
	char *endp;
	long l;

	l = strtol(string, &endp, 10);
	if (l == LONG_MIN || l == LONG_MAX)
		return (BERI_DEBUG_ERROR_REGBOUND);
	if (l < 0 || l > 31)
		return (BERI_DEBUG_ERROR_REGBOUND);
	*regnump = l;
	return (BERI_DEBUG_SUCCESS);
}

static const char * const excode2str(uint32_t code)
{
	if (code < sizeof(exception_codes)/sizeof(*exception_codes))
		return exception_codes[code];
	else if (code 	== 0xff)
		return "Invalid Op";
	else 
		return "Unknown";
}

void
print_exception(uint8_t excode)
{
	printf("Exception! Code = 0x%x (%s)\n", excode, excode2str(excode));
}

int
berictl_breakpoint(struct beri_debug *bdp, const char *addrp, int waitflag)
{
	uint64_t addr, breakpoint;
	int ret;
	uint8_t oldstate;

	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	BERI2_PAUSE(bdp, oldstate);
	printf("Setting breakpoint at 0x%016" PRIx64 "\n", addr);
	ret = beri_debug_client_breakpoint_set(bdp, 0, htob64(bdp, addr));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	BERI2_RESUME(bdp, oldstate);
	if (waitflag == 0)
		return (BERI_DEBUG_SUCCESS);
	ret = beri_debug_client_breakpoint_wait(bdp, &breakpoint);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	breakpoint = btoh64(bdp, breakpoint);
	printf("Breakpoint at 0x%016" PRIx64 " fired\n", breakpoint);
	return (beri_debug_client_breakpoint_clear(bdp, 0));
}

#ifdef BERI_NETFPGA
static int
_netfpga_sume_write(struct beri_debug *bdp, const char v)
{
	struct sume_ifreq sifr;
	int ret;

        sifr.addr = NETFPGA_AXI_JTAG_UART_BASE_ADDR;
        sifr.val = v;
	ret = beri_debug_client_netfpga_sume_ioctl(bdp, &sifr,
	    SUME_IOCTL_CMD_WRITE_REG, SUME_IFNAM_DEFAULT);
	if (ret < 0)
		return (ret);
	else
		return (1);
}

static int
_netfpga_write(struct beri_debug *bdp, const char v)
{
	uint64_t rv;
	int bd_fd, ret;

	if (beri_debug_is_netfpga_sume(bdp))
		return (_netfpga_sume_write(bdp, v));

	bd_fd = beri_debug_getfd(bdp);

	rv = ((uint64_t)(NETFPGA_AXI_JTAG_UART_BASE_ADDR) << 32) | ((v) & 0xff);
	ret = ioctl(bd_fd, NETFPGA_IOCTL_CMD_WRITE_REG, rv);
	if (ret < 0)
		return (ret);
	else
		return (1);
}

static int
_netfpga_sume_read(struct beri_debug *bdp)
{
	struct sume_ifreq sifr;
	int ret;
	char ch;

	do {
		sifr.addr = NETFPGA_AXI_JTAG_UART_BASE_ADDR;
		sifr.val = 0;
		ret = beri_debug_client_netfpga_sume_ioctl(bdp, &sifr,
		    NETFPGA_IOCTL_CMD_READ_REG, SUME_IFNAM_DEFAULT);
		if (ret == -1)
			return (ret);
		if (sifr.val & NETFPGA_AXI_FIFO_RD_BYTE_VALID_CONS) {
			ch = sifr.val & 0xff;
			(void)write(STDOUT_FILENO, &ch, sizeof(ch));
		}
	} while (sifr.val & NETFPGA_AXI_FIFO_RD_BYTE_VALID_CONS);

	return (ret);
}

static int
_netfpga_read(struct beri_debug *bdp)
{
	uint64_t rv;
	int bd_fd, ret;
	char ch;

	if (beri_debug_is_netfpga_sume(bdp))
		return (_netfpga_sume_read(bdp));

	bd_fd = beri_debug_getfd(bdp);
	do {
		rv = (uint64_t)(NETFPGA_AXI_JTAG_UART_BASE_ADDR);
		ret = ioctl(bd_fd, NETFPGA_IOCTL_CMD_READ_REG, &rv);
		if (ret == -1)
			return (ret);
		rv &= 0xffffffff;
		if (rv & NETFPGA_AXI_FIFO_RD_BYTE_VALID_CONS) {
			ch = rv & 0xff;
			(void)write(STDOUT_FILENO, &ch, sizeof(ch));
		}
	} while (rv & NETFPGA_AXI_FIFO_RD_BYTE_VALID_CONS);

	return (ret);
}
#endif

/* Attempt to kill the nios2-terminal child and restore
 * terminal functionality if we are killed
 * (eg by receiving SIGTERM)
 */
static void
berictl_console_kill_child(int rx_signal)
{
	if (rx_signal != SIGTERM)
		return;
	if (nios2_terminal_pid != 0)
	{
		//printf("Attempting to kill berictl child process %d\n",nios2_terminal_pid);
		kill(nios2_terminal_pid, SIGKILL);
		nios2_terminal_pid = 0;
		/* we try our best that struct trm_save is initialised before we get here:
		 * if it isn't we're about to die anyway so not much we can do about it
		 */
		//printf("Resetting terminal\n");
		tcsetattr(STDIN_FILENO, TCSANOW, &trm_save);
	}
	fprintf(stderr, "\r\nberictl: Terminated due to signal %d, quitting\n", rx_signal);
	exit(1);
}


#ifndef __DECONST
#define	__DECONST(type, var)	((type)(uintptr_t)(const void *)(var))
#endif
#define	CONSOLE_STATE_PLAIN	1
#define	CONSOLE_STATE_ENTER	2
#define	CONSOLE_STATE_TILDE	3
#define	CONSOLE_STATE_QUESTION	4
int
berictl_console_eventloop(struct beri_debug *bdp, int fd, pid_t pid)
{
	struct pollfd pollfd[2];
	ssize_t len;
	u_int console_state;
	int all_ones, is_netfpga, nfds, send_input, terminate;
	int8_t ch;

	/*
	 * This event loop has a historically deadlock-prone structure.
	 */
	all_ones = 0;
	is_netfpga = (bdp != NULL && (beri_debug_is_netfpga(bdp) ||
	    beri_debug_is_netfpga_sume(bdp)));
	terminate = 0;
	console_state = CONSOLE_STATE_PLAIN;
#ifdef __APPLE__
	int enabled = 1;
	if (setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &enabled, sizeof(enabled)) == -1)
	{
		perror("setsockopt");
		exit(1);
	}	
#endif

	do {
		pollfd[0].events = POLLIN;
		pollfd[0].revents = 0;
		pollfd[0].fd = STDIN_FILENO;
		if (!is_netfpga) {
			pollfd[1].events = POLLIN;
			pollfd[1].revents = 0;
			pollfd[1].fd = fd;
			nfds = poll(pollfd, 2, -1);
		} else {
			nfds = poll(pollfd, 1, 10);
		}
		if (nfds < 0) {
			warn("poll");
			continue;
		}
		if (!is_netfpga && (pollfd[1].revents & POLLIN)) {
			len = read(fd, &ch, sizeof(ch));
			if (len < 0) {
				warn("read console");
				break;
			}
			if (len == 0) {
				warnx("read console: EOF");
				break;
			}
			assert(len == sizeof(ch));
			/*
			 * When boards are reprogramed on chericloud,
			 * nios2-terminal spews an endless stream of -1's
			 * until it is disconnected.  Detect large numbers
			 * of ones in a row with no user input and restart
			 * the terminal.
			 */
			if (pid > 0 && ch == -1) {
				all_ones++;
				if (all_ones > 1000) {
					close(fd);
					kill(pid, SIGKILL);
					printf("\n");
					return (1);
				}
			} else
				all_ones = 0;
			(void)write(STDOUT_FILENO, &ch, sizeof(ch));
#ifdef BERI_NETFPGA
		} else if (is_netfpga) {
			/* Always poll the ``jtag-uart''. */
			int ret;

			ret = _netfpga_read(bdp);
			if (ret == -1) {
				warn("read console");
				break;
			}
#endif
		}
		if (pollfd[0].revents & POLLIN) {
			len = read(STDIN_FILENO, &ch, sizeof(ch));
			if (len < 0) {
				warn("read stdin");
				break;
			}
			if (len == 0) {
				warnx("read stdin");
				break;
			}

			/* Reset the count of uninterrupted 1's. */
			if (pid > 0)
				all_ones = 0;

			send_input = 1;
			if (console_state == CONSOLE_STATE_PLAIN) {
				if (ch == '\r')
					console_state = CONSOLE_STATE_ENTER;
			} else if (console_state == CONSOLE_STATE_ENTER) {
				if (ch == '~') {
					console_state = CONSOLE_STATE_TILDE;
					send_input = 0;
				} else
					console_state = CONSOLE_STATE_PLAIN;
			} else if (console_state == CONSOLE_STATE_TILDE) {
				switch (ch) {
				case '.':
					terminate = 1;
					send_input = 0;
					break;

				default:
					if (!is_netfpga)
						send(fd, "~", sizeof('~'),
						    MSG_NOSIGNAL);
#ifdef BERI_NETFPGA
					else {
						int ret;

						ret = _netfpga_write(bdp, '~');
						if (ret == -1) {
							warn("send console");
							break;
						}
					}
#endif
					console_state = CONSOLE_STATE_PLAIN;
				}
			}
			if (send_input) {
				if (!is_netfpga)
					len = send(fd, &ch, sizeof(ch),
					    MSG_NOSIGNAL);
#ifdef BERI_NETFPGA
				else
					len = _netfpga_write(bdp, ch);
#endif
				if (len < 0) {
					warn("send console");
					break;
				}
				if (len == 0) {
					warnx("send console EOF");
					break;
				}
				assert(len == sizeof(ch));
			}
		}
	} while ((pollfd[0].revents & POLLHUP) == 0 &&
	    (is_netfpga || ((pollfd[1].revents & POLLHUP) == 0)) &&
	    !terminate);

	return (0);
}

int
berictl_console(struct beri_debug *bdp, const char *filenamep,
    const char *cablep, const char *devicep)
{
	struct sockaddr_un sun;
	struct termios trm_new;
	struct sigaction signal_action;
	pid_t pid;
	int fd, restarting;
	int is_netfpga;
	int sockets[2];
	char *nios_path;
	char *argv[] = {
	    "nios2-terminal", "-q", "--no-quit-on-ctrl-d", "--instance", "1",
	    NULL, NULL, NULL, NULL, NULL };
	int argp = 5;

	if ((nios_path = getenv("BERICTL_NIOS2_TERMINAL")) != NULL)
		argv[0] = nios_path;

	is_netfpga = (bdp != NULL && (beri_debug_is_netfpga(bdp) ||
	    beri_debug_is_netfpga_sume(bdp)));
	restarting = 0;
restart:
	if (!is_netfpga && filenamep == NULL) {
		if (socketpair(AF_UNIX, SOCK_STREAM, 0, sockets) == -1) {
			warn("socketpair");
			return (BERI_DEBUG_ERROR_SOCKETPAIR);
		}
		pid = fork();
		if (pid < 0) {
			warn("fork");
			return (BERI_DEBUG_ERROR_FORK);
		} else if (pid != 0) {
			close(sockets[1]);
			fd = sockets[0];
			nios2_terminal_pid = pid;
		} else {
			close(sockets[0]);
			if (dup2(sockets[1], STDIN_FILENO) == -1 ||
			    dup2(sockets[1], STDOUT_FILENO) == -1)
				err(1, "dup2");
#ifdef __FreeBSD__
			closefrom(3);
#else
			/* XXX: weaker than ideal cleanup. */
			close(sockets[1]);
#endif
			if (cablep != NULL && *cablep != '\0') {
				argv[argp++] = "--cable";
				argv[argp++] = __DECONST(char *, cablep);
			}
			if (devicep != NULL && *devicep != '\0') {
				argv[argp++] = "--device";
				argv[argp++] = __DECONST(char *, devicep);
			}
			/*
			 * XXX: does not make it to the user, but without
			 * some output before exec we seem to get EOF and
			 * terminate the session.
			 */
			printf("starting nios2-terminal\n");
			execvp(argv[0], argv);
			if (errno == ENOENT)
				err(1, "nios2-terminal not found in PATH");
			err(1, "execvp");
		}
	} else if (!is_netfpga) {
		fd = socket(PF_LOCAL, SOCK_STREAM, 0);
		if (fd < 0) {
			warn("socket");
			return (BERI_DEBUG_ERROR_SOCKET);
		}
		memset(&sun, 0, sizeof(sun));
		sun.sun_family = AF_LOCAL;
		/* XXXRW: BSD-only: sun.sun_len = sizeof(sun); */
		strncpy(sun.sun_path, filenamep, sizeof(sun.sun_path) - 1);
		if (connect(fd, (struct sockaddr *)&sun, sizeof(sun)) < 0) {
			warn("connect: %s", filenamep);
			close(fd);
			return (BERI_DEBUG_ERROR_CONNECT);
		}
		pid = 0;
	} else if (is_netfpga)
		pid = 0;

	if (restarting)
		fprintf(stderr, "Board reset detected, reconnecting.\n");
	else
		fprintf(stderr,
		    "Connecting to BERI UART; ~. to close console.\n");

	/*
	 * Put TTY into raw mode so that we can forward character-at-a-time
	 * and let the console code running on top of BERI do its thing.
	 *
	 * XXX: should catch signals and restore tty
	 */
	if (!restarting) {
		tcgetattr(STDIN_FILENO, &trm_save);
		trm_new = trm_save;
		cfmakeraw(&trm_new);
		tcsetattr(STDIN_FILENO, TCSANOW, &trm_new);
	}

	//printf("Setting SIGTERM handler\n");
	memset(&signal_action, 0, sizeof(struct sigaction));
	signal_action.sa_handler = berictl_console_kill_child;
        sigaction(SIGTERM, &signal_action, NULL);

	restarting = berictl_console_eventloop(bdp, fd, pid);
	if (restarting != 0)
		goto restart;

	if (pid > 0)
	{
		kill(pid, SIGKILL);
		nios2_terminal_pid = 0;
	}
	close(fd);
	tcsetattr(STDIN_FILENO, TCSANOW, &trm_save);
	return (BERI_DEBUG_SUCCESS);
}

struct c0_reg_info {
	char *reg_name;
	u_int reg_num;
	u_int reg_sel;
};

#define N_C0REG 38
static struct c0_reg_info c0_registers[N_C0REG] = {
	{"Index", 0, 0},
	{"Random", 1, 0},
	{"EntryLo0", 2, 0},
	{"EntryLo1", 3, 0},
	{"Context", 4, 0},
	{"UserLocal", 4, 2},
	{"PageMask", 5, 0},
	{"Wired", 6, 0},
	{"HWREna", 7, 0},
	{"BadVAddr", 8, 0},
	{"Count", 9, 0},
	{"EntryHi", 10, 0},
	{"Compare", 11, 0},
	{"Status", 12, 0},
	{"Cause", 13, 0},
	{"EPC", 14, 0},
	{"PRId", 15, 0},
	{"CoreId", 15, 6},
	{"ThreadId", 15, 7},
	{"Config", 16, 0},
	{"Config1", 16, 1},
	{"Config2", 16, 2},
	{"Config3", 16, 3},
	{"LLAddr", 17, 0},
	{"WatchLo", 18, 0},
	{"WatchHi", 19, 0},
	{"XContext", 20, 0},
	{"-", 21, 0},
	{"-", 22, 0},
	{"-", 23, 0},
	{"-", 24, 0},
	{"-", 25, 0},
	{"ECC", 26, 0},
	{"CacheErr", 27, 0},
	{"TagLo", 28, 0},
	{"TagHi", 29, 0},
	{"ErrorEPC", 30, 0},
	{"-", 31, 0}
};

int
berictl_c0regs(struct beri_debug *bdp)
{
	uint64_t v;
	int regnum, ret;
	uint8_t oldstate;
	BERI2_PAUSE(bdp, oldstate);

	printf("======   CP0 Registers   ======\n");

	ret = beri_debug_client_pause_execution(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_a(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	for (regnum = 0; regnum < N_C0REG; regnum++) {
		ret = beri_debug_client_get_c0reg_pipelined_send(bdp,
			c0_registers[regnum].reg_num,
			c0_registers[regnum].reg_sel);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
	}
	for (regnum = 0; regnum < N_C0REG; regnum++) {
		ret = beri_debug_client_get_reg_pipelined_response(bdp, &v);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		v = btoh64(bdp, v);
		printf("[%2d:%d] %s: 0x%016" PRIx64 "\n",
			c0_registers[regnum].reg_num,
			c0_registers[regnum].reg_sel,
			c0_registers[regnum].reg_name, v);
	}

	BERI2_RESUME(bdp, oldstate);
	return BERI_DEBUG_SUCCESS;
}

void berictl_print_cap(struct cap *cap) {
  printf("tag: %d u:%d perms:0x%04" PRIx64 " type:0x%016" PRIx64 " "
	 "base:0x%016" PRIx64 " length:0x%016" PRIx64 "\n", cap->tag,
	 cap->unsealed, (uint64_t) cap->perms, cap->type, cap->base, cap->length);
}

int
berictl_c2regs(struct beri_debug *bdp)
{
  //uint64_t perms, type, base, length;
	int regnum, ret;
	struct cap cap;
	uint8_t oldstate;

	BERI2_PAUSE(bdp, oldstate);

	printf("======   RegFile   ======\n");

	ret = beri_debug_client_pause_execution(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	for (regnum = 0; regnum < 32; regnum++) {
		ret = cheri_debug_client_get_c2reg(bdp, regnum, &cap);
		if (ret != BERI_DEBUG_SUCCESS)
			return ret;
		printf("DEBUG CAP REG %2d ", regnum);
		berictl_print_cap(&cap);
	}

#ifdef BROKEN_PCC_PRINTING
	/*
	 * Retrieve and print the PCC.  This operation destroys capability
	 * register 26, the return register.
	 */
	ret = cheri_debug_client_pcc_to_cr26(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	ret = cheri_debug_client_get_c2reg(bdp,
	    CHERI_DEBUG_CAPABILITY_LINK_REG, &cap);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	printf("DEBUG CAP PCC ");
	berictl_print_cap(&cap);
#endif
	BERI2_RESUME(bdp, oldstate);
	return BERI_DEBUG_SUCCESS;
}

int
berictl_drain(struct beri_debug *bdp)
{

	printf("Draining BERI debug unit socket\n");
	return (beri_debug_client_drain(bdp));
}

int
berictl_lbu(struct beri_debug *bdp, const char *addrp)
{
	uint64_t addr;
	int ret;
	uint8_t excode, oldstate, v;

	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	if (!quietflag)
		printf("Attempting to lbu from 0x%016" PRIx64 "\n", addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_lbu(bdp, htob64(bdp, addr), &v, &excode);
	switch (ret) {
	case BERI_DEBUG_ERROR_EXCEPTION:
		/* We consider returning an exception to be a success here. */
		print_exception(excode);
		ret = BERI_DEBUG_SUCCESS;
		break;

	case BERI_DEBUG_SUCCESS:
		printf("0x%016" PRIx64 " = 0x%02x\n", addr, v);
		break;
	}
	BERI2_RESUME(bdp, oldstate);
	return (ret);
}

int
berictl_lhu(struct beri_debug *bdp, const char *addrp)
{
	uint64_t addr;
	int ret;
	uint8_t excode, oldstate;
	uint16_t v;

	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	if (!quietflag)
		printf("Attempting to lhu from 0x%016" PRIx64 "\n", addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_lhu(bdp, htob64(bdp, addr), &v, &excode);
	switch (ret) {
	case BERI_DEBUG_ERROR_EXCEPTION:
		/* We consider returning an exception to be a success here. */
		print_exception(excode);
		ret = BERI_DEBUG_SUCCESS;
		break;

	case BERI_DEBUG_SUCCESS:
		printf("0x%016" PRIx64 " = 0x%04x\n", addr, v);
		break;
	}
	BERI2_RESUME(bdp, oldstate);
	return (ret);
}

int
berictl_lwu(struct beri_debug *bdp, const char *addrp)
{
	uint64_t addr;
	int ret;
	uint8_t excode, oldstate;
	uint32_t v;

	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	if (!quietflag)
		printf("Attempting to lwu from 0x%016" PRIx64 "\n", addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_lwu(bdp, htob64(bdp, addr), &v, &excode);
	switch (ret) {
	case BERI_DEBUG_ERROR_EXCEPTION:
		/* We consider returning an exception to be a success here. */
		print_exception(excode);
		ret = BERI_DEBUG_SUCCESS;
		break;

	case BERI_DEBUG_SUCCESS:
		printf("0x%016" PRIx64 " = 0x%08x\n", addr, v);
		break;
	}
	BERI2_RESUME(bdp, oldstate);
	return (ret);
}

int
berictl_ld(struct beri_debug *bdp, const char *addrp)
{
	uint64_t addr, v;
	int ret;
	uint8_t excode, oldstate;

	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	if (!quietflag)
		printf("Attempting to ld from 0x%016" PRIx64 "\n", addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_ld(bdp, htob64(bdp, addr), &v, &excode);
	switch (ret) {
	case BERI_DEBUG_ERROR_EXCEPTION:
		/* We consider returning an exception to be a success here. */
		print_exception(excode);
		ret = BERI_DEBUG_SUCCESS;
		break;

	case BERI_DEBUG_SUCCESS:
		v = btoh64(bdp, v);
		printf("0x%016" PRIx64 " = 0x%016" PRIx64 "\n", addr, v);
		break;
	}
	BERI2_RESUME(bdp, oldstate);
	return (ret);
}

#define	PERCENTAGES_DISPLAYED	10
int
berictl_loadbin(struct beri_debug *bdp, const char *addrp,
    const char *filep)
{
	struct stat sb;
	uint8_t buf[8], excode, oldstate;
	uint64_t addr, bytes, v;
	int fd, i, outstanding, outstanding_max, ret;
	ssize_t len;
	struct xferstat xs;

	if (filep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);
	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);
	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/*
	 * Passed address must be a physical address that we can access via an
	 * uncached direct map region.  The requested address must be 64-bit
	 * aligned.  Do everything up until the last short read using 64-bit
	 * stores with pipelining, then trickle the last few bytes (if any) in
	 * using smaller sizes synchronously.
	 */
	if (addr & 0xff00000000000000) {
		warnx("Invalid physical address");
		return (BERI_DEBUG_ERROR_ADDR_INVALID);
	}
	if (addr % 8 != 0) {
		warnx("Address is not 64-bit aligned");
		return (BERI_DEBUG_ERROR_ADDR_INVALID);
	}
	addr = physical2virtual(bdp, addr);

	/*
	 * Open file; stat so that we can give a % meter status update.
	 */
	fd = open(filep, O_RDONLY);
	if (fd < 0) {
		warn("%s: open", filep);
		return (BERI_DEBUG_ERROR_OPEN);
	}
	if (fstat(fd, &sb) < 0) {
		warn("%s: fstat", filep);
		close(fd);
		return (BERI_DEBUG_ERROR_STAT);
	}

	BERI2_PAUSE(bdp, oldstate);

	stat_start(&xs, filep, sb.st_size, 0);

	/*
	 * Work loop -- submit asynchronous double word stores, keeping up to
	 * OUTSTANDING_MAX outstanding stores at any given moment.  If we
	 * reach the limit, drain one entry before letting another in.  When
	 * done (perhaps with stragglers), drain.  Maintain file endianness
	 * even though we are dealing with words and registers.
	 *
	 * XXXRW: Is this definitely right for both big- and little-endian
	 * hosts?
	 */
	outstanding_max = beri_debug_get_outstanding_max(bdp);
	bytes = 0;
	outstanding = 0;
	while ((len = read(fd, buf, sizeof(buf))) == sizeof(buf)) {
		if (outstanding == outstanding_max) {
			ret = beri_debug_client_sd_pipelined_response(bdp,
			    &excode);
			if (ret == BERI_DEBUG_ERROR_EXCEPTION) {
				close(fd);
				stat_end(&xs);
				printf("Exception!  Code = 0x%x (%s)\n", excode,
				    mips_exception_name(excode));
				return (ret);
			}
			assert(ret == BERI_DEBUG_SUCCESS);
			outstanding--;
		}
		/* Because the target is big endian we must get the correct
		 * byte order.  Note that because BERI loads its operands
		 * backwards we actually reverse twice (htobe then htob), but
		 * BERI2's protocol is little endian so we only swap once
		 * there.
		 */
		v = htobe64(*(uint64_t *)buf);
		ret = beri_debug_client_sd_pipelined_send(bdp, htob64(bdp, addr),
							   htob64(bdp, v));
		assert(ret == BERI_DEBUG_SUCCESS);
		outstanding++;
		addr += sizeof(buf);
		bytes += sizeof(buf);
		stat_update(&xs, bytes);
	}
	while (outstanding != 0) {
		ret = beri_debug_client_sd_pipelined_response(bdp, &excode);
		assert(ret == BERI_DEBUG_SUCCESS);
		outstanding--;
	}
	if (len < 0) {
		warn("%s: read", __func__);
		close(fd);
		stat_end(&xs);
		return (BERI_DEBUG_ERROR_READ);
	}

	/*
	 * Write last few bytes, byte at a time.
	 */
	for (i = 0; i < len; i++) {
	  ret = beri_debug_client_sb(bdp, htob64(bdp, addr), buf[i],
		    &excode);
		assert(ret == BERI_DEBUG_SUCCESS);
		addr++;
	}
	BERI2_RESUME(bdp, oldstate);
	close(fd);
	stat_end(&xs);
	return (BERI_DEBUG_SUCCESS);
}

int
berictl_loadsof(const char *filep, const char *cablep, const char *devicep)
{
	char *quartus_path, *realfilep;
	char *quartus_cmd[] =
	    { "quartus_pgm", "-m", "jtag", "-o", NULL, NULL, NULL, NULL };

	if (filep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	if (cablep != NULL) {
		quartus_cmd[5] = "-c";
		quartus_cmd[6] = __DECONST(char *, cablep);
	}

	if ((quartus_path = getenv("BERICTL_QUARTUS_PGM")) != NULL)
		quartus_cmd[0] = quartus_path;

	if ((realfilep = realpath(filep, NULL)) == NULL) {
		warn("realpath(%s)", filep);
		return (BERI_DEBUG_USAGE_ERROR);
	}

	if (asprintf(&quartus_cmd[4], "P;%s%s%s", realfilep,
		(devicep == NULL) ? "" : "@",
		(devicep == NULL) ? "" : devicep ) == -1)
	{
		free(realfilep);
		return (BERI_DEBUG_ERROR_MALLOC);
	}

	/* XXX-library: should fork and monitor child */
	execvp(quartus_cmd[0], quartus_cmd);
	if (errno == ENOENT)
		err(1, "%s not found in PATH", quartus_cmd[0]);
	err(1, "execvp");

	/*NOTREACHED*/
}

int
berictl_reset(struct beri_debug *bdp)
{
	int ret;

	ret = beri_debug_client_reset(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	printf("CPU reset\n");
	return (BERI_DEBUG_SUCCESS);
}

int
berictl_pause(struct beri_debug *bdp)
{
	uint64_t addr;
	int ret;

	ret = beri_debug_client_pause_execution(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_get_pc(bdp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	addr = btoh64(bdp, addr);
	printf("CPU paused at %016" PRIx64 "\n", addr);
	return (BERI_DEBUG_SUCCESS);
}

int
berictl_unpipeline(struct beri_debug *bdp)
{
	int ret;

	ret = beri_debug_client_unpipeline_execution(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	printf("CPU running unpipelined\n");
	return (BERI_DEBUG_SUCCESS);
}

int
berictl_pc(struct beri_debug *bdp)
{
	uint64_t addr;
	int ret;
	uint8_t oldstate = 0xff;

	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_get_pc(bdp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	BERI2_RESUME(bdp, oldstate);
	addr = btoh64(bdp, addr);
	printf("DEBUG MIPS PC 0x%016" PRIx64 "\n", addr);
	return (BERI_DEBUG_SUCCESS);
}

int
berictl_regs(struct beri_debug *bdp)
{
	uint64_t v;
	int regnum, ret;
	uint8_t oldstate;
	BERI2_PAUSE(bdp, oldstate);
	printf("======   RegFile   ======\n");
	ret = beri_debug_client_pause_execution(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = berictl_pc(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_a(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_load_operand_b(bdp, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	printf("DEBUG MIPS REG %2d 0x%016" PRIx64 "\n", 0, (uint64_t) 0);
	for (regnum = 1; regnum < 32; regnum++) {
		ret = beri_debug_client_get_reg_pipelined_send(bdp,
		    regnum);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
	}
	for (regnum = 1; regnum < 32; regnum++) {
		ret = beri_debug_client_get_reg_pipelined_response(bdp, &v);
		if (ret != BERI_DEBUG_SUCCESS)
			return (ret);
		v = btoh64(bdp, v);
		printf("DEBUG MIPS REG %2d 0x%016" PRIx64 "\n", regnum, v);
	}
	BERI2_RESUME(bdp, oldstate);
	return BERI_DEBUG_SUCCESS;
}

int
berictl_resume(struct beri_debug *bdp)
{
	uint64_t addr;
	int ret;
	uint8_t oldstate;

	BERI2_PAUSE(bdp, oldstate);	/* No matching BERI2_RESUME */
	ret = beri_debug_client_get_pc(bdp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_resume_execution(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	addr = btoh64(bdp, addr);
	if (!quietflag)
		printf("CPU resumed at %016" PRIx64 "\n", addr);
	return (BERI_DEBUG_SUCCESS);
}

int
berictl_sb(struct beri_debug *bdp, const char *addrp, const char *valuep)
{
	uint64_t addr, v;
	int ret;
	uint8_t excode, oldstate;

	if (addrp == NULL || valuep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = hex2addr(valuep, &v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	v &= 0xff;
	if (!quietflag)
		printf("Attempting to sb 0x%02x to 0x%016" PRIx64 "\n", (uint8_t)v, addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_sb(bdp, htob64(bdp, addr), v, &excode);
	switch (ret) {
	case BERI_DEBUG_ERROR_EXCEPTION:
		/* We consider returning an exception to be a success here. */
		print_exception(excode);
		ret = BERI_DEBUG_SUCCESS;
		break;

	case BERI_DEBUG_SUCCESS:
		printf("0x%016" PRIx64 " = 0x%02" PRIx64 "\n", addr, v);
		break;
	}
	BERI2_RESUME(bdp, oldstate);
	return (ret);
}

int
berictl_sh(struct beri_debug *bdp, const char *addrp, const char *valuep)
{
	uint64_t addr, v;
	int ret;
	uint8_t excode, oldstate;

	if (addrp == NULL || valuep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = hex2addr(valuep, &v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	v &= 0xffff;
	if (!quietflag)
		printf("Attempting to sh 0x%04x to 0x%016" PRIx64 "\n", (uint16_t)v,
		    addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_sh(bdp, htob64(bdp, addr), v, &excode);
	switch (ret) {
	case BERI_DEBUG_ERROR_EXCEPTION:
		/* We consider returning an exception to be a success here. */
		print_exception(excode);
		ret = BERI_DEBUG_SUCCESS;
		break;

	case BERI_DEBUG_SUCCESS:
		printf("0x%016" PRIx64 " = 0x%04" PRIx64 "\n", addr, v);
		break;
	}
	BERI2_RESUME(bdp, oldstate);
	return (ret);
}

int
berictl_sw(struct beri_debug *bdp, const char *addrp, const char *valuep)
{
	uint64_t addr, v;
	int ret;
	uint8_t excode, oldstate;

	if (addrp == NULL || valuep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = hex2addr(valuep, &v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	v &= 0xffffffff;
	if (!quietflag)
		printf("Attempting to sw 0x%08x to 0x%016" PRIx64 "\n", (uint32_t)v,
		    addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_sw(bdp, htob64(bdp, addr), v, &excode);
	switch (ret) {
	case BERI_DEBUG_ERROR_EXCEPTION:
		/* We consider returning an exception to be a success here. */
		print_exception(excode);
		ret = BERI_DEBUG_SUCCESS;
		break;

	case BERI_DEBUG_SUCCESS:
		printf("0x%016" PRIx64 " = 0x%08" PRIx64 "\n", addr, v);
		break;
	}
	BERI2_RESUME(bdp, oldstate);
	return (ret);
}

int
berictl_sd(struct beri_debug *bdp, const char *addrp, const char *valuep)
{
	uint64_t addr, v;
	int ret;
	uint8_t excode, oldstate;

	if (addrp == NULL || valuep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = hex2addr(valuep, &v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	if (!quietflag)
		printf("Attempting to sd %016" PRIx64 " to 0x%016" PRIx64 "\n", v, addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_sd(bdp, htob64(bdp, addr), htob64(bdp, v), &excode);
	switch (ret) {
	case BERI_DEBUG_ERROR_EXCEPTION:
		/* We consider returning an exception to be a success here. */
		print_exception(excode);
		ret = BERI_DEBUG_SUCCESS;
		break;
	case BERI_DEBUG_SUCCESS:
		printf("0x%016" PRIx64 " = 0x%016" PRIx64 "\n", addr, v);
		break;
	}
	BERI2_RESUME(bdp, oldstate);
	return (ret);
}

int
berictl_setpc(struct beri_debug *bdp, const char *addrp)
{
	uint64_t addr;
	int ret;
	uint8_t oldstate;

	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	printf("Jumping to %016" PRIx64 "\n", addr);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_set_pc(bdp, htob64(bdp, addr));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_get_pc(bdp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	BERI2_RESUME(bdp, oldstate);
	printf("New PC of %016" PRIx64 "\n", btoh64(bdp, addr));
	return (BERI_DEBUG_SUCCESS);
}

int
berictl_setthread(struct beri_debug *bdp, const char *valuep)
{
	int ret;
	uint8_t oldstate;
	uint8_t threadID;

	if (valuep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);
	threadID = (uint8_t) strtol(valuep, NULL, 0);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_set_thread(bdp, threadID);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	BERI2_RESUME(bdp, oldstate);
	printf("Now debuging thread %d\n", threadID);
	return (ret);
}

int
berictl_setreg(struct beri_debug *bdp, const char *regnump,
    const char *valuep)
{
	uint64_t v;
	u_int regnum;
	int ret;
	uint8_t oldstate;

	if (regnump == NULL || valuep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	ret = str2regnum(regnump, &regnum);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = hex2addr(valuep, &v);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_set_reg(bdp, regnum, htob64(bdp, v));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	BERI2_RESUME(bdp, oldstate);
	printf("Set $%d to %016" PRIx64 "\n", regnum, v);
	return (ret);
}

int
berictl_step(struct beri_debug *bdp)
{
	uint64_t before, after;
	int ret;
	uint8_t oldstate;

	BERI2_PAUSE(bdp, oldstate);
	ret = beri_debug_client_get_pc(bdp, &before);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_step_execution(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = beri_debug_client_get_pc(bdp, &after);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	BERI2_RESUME(bdp, oldstate);
	printf("Single-stepped CPU from 0x%016" PRIx64 " to 0x%016" PRIx64 "\n",
	    btoh64(bdp, before), btoh64(bdp, after));
	return (BERI_DEBUG_SUCCESS);
}

int
berictl_test_run(struct beri_debug *bdp)
{
	int ret;
	char pc[20];
	strcpy(pc, "9000000040000000");
	ret = berictl_pause(bdp);
	printf("Draining trace buffer:\n");
	ret = berictl_stream_trace(bdp, 1, 0, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = berictl_setpc(bdp, pc);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	//ret = berictl_resume(bdp);
	int streamTimes = 16;
	int binary = 0;
	ret = berictl_stream_trace(bdp, streamTimes, binary, 0);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	// Sleep for 200ms to allow the test to execute.
	//usleep(200000);
	return(berictl_pause(bdp));
}

int
berictl_test_report(struct beri_debug *bdp)
{
	int ret;
	ret = berictl_regs(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	ret = berictl_c2regs(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	return (berictl_c0regs(bdp));
}

uint64_t
expand_address(uint32_t shrt)
{
	uint64_t addr = 0;
	uint64_t cmp = (uint64_t) shrt;
	// Move 4 bits of the segment up to the top.
	addr |= (cmp & 0xF0000000)<<31;
	// If the address segment was non-zero, set the top bit also.
	if (addr != 0) addr |= 0x8000000000000000;
	// Shift up the top bits of the 40-bit virtual address
	addr |= (cmp & 0x0FF00000)<<12;
	if (addr & 0x8000000000) addr |= 0x07FFFF0000000000;
	// Or in the bottom 20 bits of the 40-bit virtual address.
	addr |= (cmp & 0x000FFFFF);
	// (There will be 12 zeroed bits in the middle where address information is missing)
	return addr;
}

static void
print_trace_entry(struct beri_debug_trace_entry *tep)
{
  static uint64_t global_cycle_count = 0;
  static uint64_t global_instruction_count = 0;
	if (tep->exception != 31)
		printf("  Exception Code:0x%2.2x(%s) ", tep->exception, excode2str(tep->exception));
	if (!tep->valid)
		printf(" !CANCELED! ");
	// Use the lower 10 bits from the instruction count and the upper bits
	// from the global counter.
	if (tep->version != 4) {
	  printf("Time=%16ld : ", (long int)(global_cycle_count&(~0x3ff))|tep->cycles);
	  uint64_t pc = tep->pc;
	  if (tep->version == 12 || tep->version == 13) pc = 0;
	  mips_cpu_disassemble_instr((unsigned char *)&tep->inst, pc);
	}
	if (tep->branch) printf(" branch to 0x%16.16" PRIx64 "", tep->val1);
	switch (tep->version) {
  case 0:
	  printf(" {%d}\n", tep->asid);
	  break;
  case 1:
	  printf("  DestReg <- 0x%16.16" PRIx64 " {%d}\n", tep->val2, tep->asid);
	  break;
  case 2:
	  printf("  DestReg <- 0x%16.16" PRIx64 " from Address 0x%16.16" PRIx64 " {%d}\n",
	      tep->val2, tep->val1, tep->asid);
	  break;
  case 3:
	  printf("  Address 0x%16.16" PRIx64 " <- 0x%16.16" PRIx64 " {%d}\n",
	     tep->val1, tep->val2, tep->asid);
	  break;
	case 4:
    printf("  CPI %16.16f\n", (double)(tep->val1 - global_cycle_count)/
        (double)(tep->val2 - global_instruction_count));
	  global_cycle_count = tep->val1;
	  global_instruction_count = tep->val2;
	  break;
	case 11:
	  printf("  CapReg <- tag:%1" PRIx64 " u:%1" PRIx64 " perms:0x%8.8" PRIx64 " type:0x%6.6" PRIx64 " offset:0x%16.16" PRIx64 " base:0x%16.16" PRIx64 " length:0x%16.16" PRIx64 " {%d}\n", 
	  	(tep->val2>>63) & 0x1,
	  	(tep->val2>>62) & 0x1,
	  	(tep->val2>>53) & 0xFF,
	  	(tep->val2>>32) & 0x3FFFFF,
	  	expand_address((uint32_t)((tep->val2>>0)  & 0xFFFFFFFF)),
	  	expand_address((uint32_t)((tep->val1>>32) & 0xFFFFFFFF)),
	  	expand_address((uint32_t)((tep->val1>>0)  & 0xFFFFFFFF)),
	  	tep->asid);
	  break;
	case 12:
	  printf("  CapReg <- tag:%1" PRIx64 " u:%1" PRIx64 " perms:0x%8.8" PRIx64 " type:0x%6.6" PRIx64 " offset:0x%16.16" PRIx64 " base:0x%16.16" PRIx64 " length:0x%16.16" PRIx64 " from Address 0x%16.16" PRIx64 " {%d}\n",
	    (tep->val2>>63) & 0x1,
	  	(tep->val2>>62) & 0x1,
	  	(tep->val2>>53) & 0xFF,
	  	(tep->val2>>32) & 0x3FFFFF,
	  	expand_address((uint32_t)((tep->val2>>0)  & 0xFFFFFFFF)),
	  	expand_address((uint32_t)((tep->pc>>32) & 0xFFFFFFFF)),
	  	expand_address((uint32_t)((tep->pc>>0)  & 0xFFFFFFFF)),
	  	tep->val1,
	  	tep->asid);
	  break;
  case 13:
	  printf("  Address 0x%16.16" PRIx64 " <- tag:%1" PRIx64 " u:%1" PRIx64 " perms:0x%8.8" PRIx64 " type:0x%6.6" PRIx64 " offset:0x%16.16" PRIx64 " base:0x%16.16" PRIx64 " length:0x%16.16" PRIx64 " {%d}\n",
	    tep->val1, 
	    (tep->val2>>63) & 0x1,
			(tep->val2>>62) & 0x1,
			(tep->val2>>53) & 0xFF,
			(tep->val2>>32) & 0x3FFFFF,
			expand_address((uint32_t)((tep->val2>>0)  & 0xFFFFFFFF)),
			expand_address((uint32_t)((tep->pc>>32) & 0xFFFFFFFF)),
			expand_address((uint32_t)((tep->pc>>0)  & 0xFFFFFFFF)),
			tep->asid);
	  break;
	default:
		printf("\n");
		break;
	}
}

int
berictl_stream_trace(struct beri_debug *bdp, int size, int binary, int version)
{
	int ret;
	int count;
	int i;
	int stop;
	int totCyc;
	int lastCyc;
	double cpi;
	struct beri_debug_trace_entry te;
	
	signal(SIGINT, intHandler);
	if (version == 2)
	{
		/* For later version of trace format include a file
		   header. This consists of a trace entry with a
		   version field of 0x80 + the trace version number
		   (so it won't be mistaken for a valid trace entry),
		   followed by the string 'CheriStreamTrace' to help
		   with identification. The header is the same size as
		   a trace entry to aid with seeking and to allow
		   trace files to be concatenated trivially. */
		struct beri_debug_trace_entry_disk_v2 e;
		bzero(&e, sizeof(e));
		snprintf((void *) &e, sizeof(e), "%cCheriStreamTrace", ((uint8_t)0x80) + ((uint8_t) version));
		fwrite(&e, sizeof(e), 1, stdout);
	}
	totCyc = 0;
	count = 0;
	for (i=0; i<size; i++) {
		fprintf(stderr, "Starting stream.\n");
		ret = beri_debug_client_stream_trace_start(bdp);
		if (ret != BERI_DEBUG_SUCCESS)
			return ret;
		stop = 0;
		while (!stop) {
			ret = beri_debug_client_pop_trace_receive(bdp, &te);
			if (ret != BERI_DEBUG_SUCCESS) {
				stop = 1;
				cpi = ((double)totCyc)/((double)count);
				fprintf(stderr, "Streamed %d trace entries. CPI %1.3f", count, cpi);
				if (i==size-1) fprintf(stderr, " Leaving processor paused.\n");
				else fprintf(stderr, "\n");
				totCyc = 0;
				count = 0;
			} else {
        count++;
        /*if (te.cycles > lastCyc + 1 && !binary)
          printf("%d dead cycles \n",
              te.cycles - lastCyc - 1);
        */
        if (count!=0 && (te.cycles - lastCyc > 0))
          totCyc += te.cycles - lastCyc;
        lastCyc = te.cycles;
        if (binary) {
          if (!te.valid)
            continue;
          if (version == 2) {
            struct beri_debug_trace_entry_disk_v2 e;
            e.version = te.version;
            e.exception = te.exception;
            e.cycles = htobe16((uint16_t)te.cycles);
            e.inst = te.inst;
            e.pc = htobe64(te.pc);
            e.val1 = htobe64(te.val1);
            e.val2 = htobe64(te.val2);
            e.asid= te.asid;
            e.thread = te.reserved;
            fwrite(&e, sizeof(e), 1, stdout);
          } else {
            struct beri_debug_trace_entry_disk e;
            e.version = te.version;
            e.exception = te.exception;
            e.cycles = htobe16((uint16_t)te.cycles);
            e.inst = te.inst;
            e.pc = htobe64(te.pc);
            e.val1 = htobe64(te.val1);
            e.val2 = htobe64(te.val2);
            fwrite(&e, sizeof(e), 1, stdout);
          }
        } else
          print_trace_entry(&te);
      }
		}
		if (!keepRunning) return BERI_DEBUG_SUCCESS;
	}

	return BERI_DEBUG_SUCCESS;
}

int
berictl_print_traces(struct beri_debug *bdp, const char *file)
{
	int fd;
	long nentries;
	struct stat sb;
	struct beri_debug_trace_entry_disk *entries;
	struct beri_debug_trace_entry te;

	if ((fd = open(file, O_RDONLY)) == -1) {
		warn("open(%s)", file);
		return (BERI_DEBUG_USAGE_ERROR);
	}
	if (fstat(fd, &sb) == -1) {
		warn("fstat(%s)", file);
		return (BERI_DEBUG_USAGE_ERROR);
	}
	if (sb.st_size % sizeof(*entries) != 0) {
		warnx("%s not a multiple of %zd", file, sizeof(*entries));
		return (BERI_DEBUG_USAGE_ERROR);
	}

	if ((entries = mmap(NULL, sb.st_size, PROT_READ, 0, fd, 0)) == NULL) {
		warn("mmap(%s)", file);
		return (BERI_DEBUG_USAGE_ERROR);
	}
	nentries = sb.st_size / sizeof(*entries);
	for ( ; nentries > 0; entries++, nentries--) {
		te.valid = 1;	/* We don't write cancled instructions */
		te.version = entries->version;
		te.exception = entries->exception;
		te.cycles = be16toh(entries->cycles);
		te.inst = entries->inst;
		te.pc = btoh64(bdp, entries->pc);
		te.val1 = btoh64(bdp, entries->val1);
		te.val2 = btoh64(bdp, entries->val2);
		print_trace_entry(&te);
	}

	return (BERI_DEBUG_SUCCESS);
}

int
berictl_get_parameter(char *search_string, uint64_t *par)
{
	FILE * fp;
	char found_string[128];
	int i;
	fp = fopen ("stream_trace_filter.config", "r");
	if (!fp) {
		printf("Creating stream_trace_filter.config\n");
		fp = fopen ("stream_trace_filter.config", "w+");
		fprintf(fp, "%s %s\n", "validMask", 		"0000000000000000");
		fprintf(fp, "%s %s\n", "valid", 		"0000000000000001");
		fprintf(fp, "%s %s\n", "versionMask", 		"0000000000000000");
		fprintf(fp, "%s %s\n", "version", 		"000000000000000F");
		fprintf(fp, "%s %s\n", "exceptionMask",		"0000000000000000");
		fprintf(fp, "%s %s\n", "exception", 		"000000000000001F");
		fprintf(fp, "%s %s\n", "instructionMask",	"0000000000000000");
		fprintf(fp, "%s %s\n", "instruction", 		"00000000FFFFFFFF");
		fprintf(fp, "%s %s\n", "pcMask",		"0000000000000000");
		fprintf(fp, "%s %s\n", "pc", 			"FFFFFFFFFFFFFFFF");
		fprintf(fp, "%s %s\n", "value1Mask",		"0000000000000000");
		fprintf(fp, "%s %s\n", "value1",		"FFFFFFFFFFFFFFFF");
		fprintf(fp, "%s %s\n", "value2Mask",		"0000000000000000");
		fprintf(fp, "%s %s\n", "value2",		"FFFFFFFFFFFFFFFF");
		fclose(fp);
		fp = fopen ("stream_trace_filter.config", "r");
		if (!fp) return BERI_DEBUG_USAGE_ERROR;
		printf("Finished\n");
	}
	for (i=0; i<14; i++) {
		fscanf(fp, "%s %16" PRIx64 "\n", found_string, par);
		if (!strcmp(search_string, found_string)) {
			fclose(fp);
			return BERI_DEBUG_SUCCESS;
		}
	}
	fclose(fp);
	return BERI_DEBUG_USAGE_ERROR;
}

int
berictl_set_trace_filter(struct beri_debug *bdp)
{
	int ret;
	uint64_t inLong;
	uint8_t  oldstate;

	struct beri_debug_trace_entry tm;
	struct beri_debug_trace_entry tf;
	tm = (const struct beri_debug_trace_entry){ 0 };
	tf = (const struct beri_debug_trace_entry){ 0 };
	
	// valid field
	ret = berictl_get_parameter("validMask", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tm.valid = inLong;
	ret = berictl_get_parameter("valid", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tf.valid = inLong;
	
	// version field
	ret = berictl_get_parameter("versionMask", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tm.version = inLong;
	ret = berictl_get_parameter("version", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tf.version = inLong;
	
	// exception field
	ret = berictl_get_parameter("exceptionMask", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tm.exception = inLong;
	ret = berictl_get_parameter("exception", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tf.exception = inLong;
	
	// instruction field
	ret = berictl_get_parameter("instructionMask", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tm.inst = (uint32_t)inLong;
	ret = berictl_get_parameter("instruction", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tf.inst = (uint32_t)inLong;
	
	// pc field
	ret = berictl_get_parameter("pcMask", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tm.pc = inLong;
	ret = berictl_get_parameter("pc", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tf.pc = inLong;
	
	// value1 field
	ret = berictl_get_parameter("value1Mask", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tm.val1 = inLong;
	ret = berictl_get_parameter("value1", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tf.val1 = inLong;
	
	// value2 field
	ret = berictl_get_parameter("value2Mask", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tm.val2 = inLong;
	ret = berictl_get_parameter("value2", &inLong);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	tf.val2 = inLong;

	BERI2_PAUSE(bdp, oldstate);

	printf("From stream_trace_filter.config:\n");
	printf("Trace Filter: version=%x, exception=0x%x, \
		inst=0x%8.8x, pc=0x%16.16" PRIx64 ", val1=0x%16.16" PRIx64 ", val2=0x%16.16" PRIx64 "\n", 
		tf.version, tf.exception, tf.inst, tf.pc, 
		tf.val1, tf.val2);
	ret = beri_trace_filter_mask_set(bdp, &tm);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);
	printf("Trace Mask: version=%x, exception=0x%x, \
		inst=0x%8.8x, pc=0x%16.16" PRIx64 ", val1=0x%16.16" PRIx64 ", val2=0x%16.16" PRIx64 "\n", 
		tm.version, tm.exception, tm.inst, tm.pc, 
		tm.val1, tm.val2);
	ret = beri_trace_filter_set(bdp, &tf);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	BERI2_RESUME(bdp, oldstate);

	return BERI_DEBUG_SUCCESS;
}

int
berictl_mem_trace(struct beri_debug *bdp, const char *valuep)
{
	long int longTraceEntries;
	uint32_t traceEntries;

	longTraceEntries = strtol(valuep, NULL, 0);
	if (errno == ERANGE || 
			longTraceEntries < 0 || 
			longTraceEntries > (1 << 27)) {
		return BERI_DEBUG_ERROR_INVALID_TRACECOUNT;
	}

	traceEntries = (uint32_t)longTraceEntries;

	return beri_debug_client_packet_write(bdp, BERI_DEBUG_OP_MEM_TRACE, 
			&traceEntries, 4);
}
