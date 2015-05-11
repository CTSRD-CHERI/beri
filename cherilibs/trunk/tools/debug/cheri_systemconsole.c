/*-
 * Copyright (c) 2012-2013 Bjoern A. Zeeb
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Jonathan Anderson
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

/* Allow use of (v)asprintf on linux */
#define _GNU_SOURCE

#include <sys/types.h>
#include <sys/file.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>

#include <assert.h>
#include <ctype.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <signal.h>
#include <stdarg.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "../../include/cheri_debug.h"
#include "altera_systemconsole.h"
#include "cherictl.h"

#define	SC_PID_FILE	"system-console.pid"
#define	SC_PORT_FILE	"system-console.port"

#ifndef MAX
#define MAX(a,b) (((a) > (b)) ? (a) : (b))
#endif

/* We are possibly expecting up to 8 (support up to 32) paths + surroundings. */
#define	MAX_PATH_LEN	(32 * 80 + 40)

struct beri_debug;

static struct altera_syscons_parser *parser = NULL;
static pid_t spawning_console;

static int
berictl_sc_read(int bd_fd, char *buf, size_t buflen,
    const char **begin, const char **end)
{
	int ret, l;

	if (!quietflag)
		fprintf(stderr, "%ju Waiting for response...",
		    (uintmax_t) time(NULL));

	l = 0;
again:
	assert(buflen > l);
	ret = recv(bd_fd, buf + l, buflen - l, MSG_DONTWAIT);
	if (ret >= 0)
		l += ret;
	else {
		if (errno == EAGAIN)
			goto again;
		else {
			fprintf(stderr, "read(2) %d\n", errno);
			return (BERI_DEBUG_ERROR_READ);
		}
	}

	/*
	 * If we don't have a response parser yet, we should be executing
	 * a "get_version" command, whose response will tell us the parser
	 * that we need to use.
	 */
	if (parser == NULL) {
		assert(buf != NULL);

		parser = altera_choose_parser(buf);
		ret = (parser
			? BERI_DEBUG_SUCCESS
			: BERI_DEBUG_ERROR_DATA_UNEXPECTED);
	} else {
		ret = parser->parse_response(buf, l, begin, end);
		if (ret == BERI_DEBUG_ERROR_INCOMPLETE)
			goto again;
	}

	fprintf(stderr, " done.\n");
	return (ret);
}

static int
berictl_sc_run_command(int bd_fd, char *rbuf, size_t rbufsize,
    const char *fmt, ...)
{
	int ret = BERI_DEBUG_SUCCESS, sent;
	size_t bufsize;
	char *buf = NULL, *command = NULL, *command_crlf = NULL;
	const char *begin, *end;
	va_list ap;

	va_start(ap, fmt);

	bufsize = MAX(rbufsize, MAX_PATH_LEN);
	if ((buf = calloc(1, bufsize)) == NULL) {
		ret = BERI_DEBUG_ERROR_MALLOC;
		goto done;
	}

	if (vasprintf(&command, fmt, ap) == -1) {
		ret = BERI_DEBUG_ERROR_MALLOC;
		goto done;
	}

	if (asprintf(&command_crlf, "%s\r\n", command) == -1) {
		ret = BERI_DEBUG_ERROR_MALLOC;
		goto done;
	}

	/*
	 * If we don't have a parser, we need to ask system-console what
	 * version of the protocol it speaks.
	 */
	if ((parser == NULL) && strcmp(command, "get_version") != 0) {
		ret = berictl_sc_run_command(bd_fd, NULL, 0, "get_version");
		if (ret != BERI_DEBUG_SUCCESS)
			goto done;

		assert(parser != NULL);
		if (!quietflag)
			fprintf(stderr, "%ju Using protocol: %s\n",
			    (uintmax_t)time(NULL), parser->asp_name);
	}

	if (!quietflag)
		fprintf(stderr, "%ju Command: %s\n", (uintmax_t)time(NULL),
		    command);

	/* XXX: should send in a proper loop */
	sent = send(bd_fd, command_crlf, strlen(command_crlf), 0);
	if (sent != (strlen(command_crlf))) {
		ret = BERI_DEBUG_ERROR_SEND;
		goto done;
	}

	ret = berictl_sc_read(bd_fd, buf, bufsize, &begin, &end);
	if (ret != BERI_DEBUG_SUCCESS)
		goto done;
	if (rbuf != NULL) {
		assert(rbufsize > (end - begin));
		memcpy(rbuf, begin, (end - begin));
		rbuf[(end - begin)] = '\0';
	}

done:
	va_end(ap);
	if (ret == BERI_DEBUG_ERROR_ALTERA_SOFTWARE) {
		char error[end - begin + 1];
		strncpy(error, begin, end - begin);
		error[end - begin] = '\0';
		fprintf(stderr, "%ju Error: %s\n",
			(uintmax_t)time(NULL), error);
	}
	free(buf);
	free(command);
	free(command_crlf);
	return (ret);
}

int
berictl_get_service_path(struct beri_debug *bdp, const char *cablep,
	    char *path, size_t len)
{
	const char *begin, *end;
	int bd_fd, ret;

	assert(path != NULL);

	bd_fd = beri_debug_getfd(bdp);

	ret = berictl_sc_run_command(bd_fd, path, len,
	    "get_service_paths master");
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	assert(parser != NULL);

	ret = parser->parse_service_path(path, len, cablep, &begin, &end);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	memcpy(path, begin, end - begin);
	path[end - begin] = '\0';

	if (!quietflag)
		fprintf(stderr, "%ju Path: %s\n", (uintmax_t) time(NULL), path);

	return (ret);
}

int
berictl_loaddram(struct beri_debug *bdp, const char *addrp,
    const char *filep, const char *cablep)
{
	char path[MAX_PATH_LEN], *realfilep;
	int bd_fd, ret;

	if (filep == NULL)
		return (BERI_DEBUG_USAGE_ERROR);
	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);

	bd_fd = beri_debug_getfd(bdp);

	ret = berictl_get_service_path(bdp, cablep, path, sizeof(path));
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	ret = berictl_sc_run_command(bd_fd, NULL, 0,
	    "open_service master \"%s\"", path);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	if ((realfilep = realpath(filep, NULL)) == NULL) {
		warn("realpath(%s)", filep);
		return (BERI_DEBUG_USAGE_ERROR);
	}
	ret = berictl_sc_run_command(bd_fd, NULL, 0,
	    "master_write_from_file \"%s\" %s %s", path, realfilep, addrp);
	free(realfilep);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	/* Give the FPGA a moment to settle */
	sleep(1);
	ret = berictl_sc_run_command(bd_fd, NULL, 0,
	    "close_service master \"%s\"", path);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	if (!quietflag)
		fprintf(stderr, "%ju Done\n", (uintmax_t)time(NULL));

	return (ret);
}

static void
kill_spawning_console(void)
{

	if (spawning_console != 0)
		altera_sc_stop(spawning_console);
	spawning_console = 0;
}

int
altera_sc_start(pid_t *pidp, int *portp)
{
	char buf[1024], *bufp;
	int fds[2];
	pid_t pid, port;
	ssize_t len;
	char *sc_path;
	char *sc_cmd[] = { "system-console", "--server", NULL };
	const char port_prefix[] = "TCP PORT: ";
	struct sigaction osa, sa;

	if ((sc_path = getenv("BERICTL_SYSTEM_CONSOLE")) != NULL)
		sc_cmd[0] = sc_path;

	if (socketpair(AF_UNIX, SOCK_STREAM, 0, fds) == -1) {
		warn("socketpair");
		return (-1);
	}
	pid = fork();
	if (pid == -1)
		return (-1);
	else if (pid == 0) {
		close(fds[0]);
		/* Ignore SIGHUP  so the parent can exit */
		sigemptyset(&sa.sa_mask);
		sa.sa_handler = SIG_IGN;
		sa.sa_flags = 0;
		sigaction(SIGHUP, &sa, &osa);

		dup2(fds[1], 0);
		dup2(fds[1], 1);
		dup2(fds[1], 2);
		if (fds[1] > 2)
			close (fds[1]);
		setpgid(0, 0);
		execvp(sc_cmd[0], sc_cmd);
		err(1, "execvp");
	} else {
		spawning_console = pid;
		/* Set up an atexit handler in case we're interrupted */
		atexit(kill_spawning_console);
		close(fds[1]);

		/* XXX add timeout? */
		if ((len = read(fds[0], buf, sizeof(buf))) < 0) {
			warn("system-console child error");
			kill_spawning_console();
			return (-1);
		}
		close(fds[0]);

		if (len <= strlen(port_prefix) && strncmp(buf,
		    port_prefix, strlen(port_prefix) != 0)) {
			warnx("unexpected output from system-console");
			warnx("expected '%s...'", port_prefix);
			warnx("got '%.*s'", (int)len, buf);
			kill_spawning_console();
			return (-1);
		}
		bufp = buf + strlen(port_prefix);
		if (!isdigit(bufp[0])) {
			warnx("No TCP port number found");
			warnx("got '%.*s'", (int)len, buf);
			kill_spawning_console();
			return (-1);
		}
		port = strtol(bufp, NULL, 10);
		/* Ensure the atexit handler doesn't kill the console */
		spawning_console = 0;
		*pidp = pid;
		*portp = port;
		return(0);
	}
}

void
altera_sc_stop(pid_t pid)
{

	kill(-pid, 9);
}

static int
open_berictl_dir(int nocreate)
{
	int ccd = -1;
	char *home;
	static char *berictl_dir;

	if (berictl_dir == NULL) {
		berictl_dir = getenv("BERICLT_DIR");
		if (berictl_dir == NULL &&
		    (berictl_dir = getenv("CHERICLT_DIR")) != NULL)
			warnx("CHERICLT_DIR is deprecated, use BERICLT_DIR");
		if (berictl_dir == NULL && (home = getenv("HOME")) != NULL &&
			asprintf(&berictl_dir, "%s/.berictl", home) == -1)
				berictl_dir = NULL;
		if (berictl_dir == NULL) {
			warnx("failed to find a berictl dir, "
			    "set HOME or BERICLT_DIR");
			return (-1);
		}
	}

	if ((ccd = open(berictl_dir, O_RDONLY|O_DIRECTORY)) == -1 &&
	    !nocreate) {
		if (errno == ENOENT) {
			if (mkdir(berictl_dir, 0777) == -1)
				warn("can't create %s", berictl_dir);
			else
				if ((ccd = open(berictl_dir,
				    O_RDONLY|O_DIRECTORY)) == -1)
					warn("can't open %s after creation",
					    berictl_dir);
		} else
			warn("can't open %s", berictl_dir);
	}

	if (ccd != -1 && flock(ccd, LOCK_EX) == -1)
		warn("Failed to obtain lock on %s", berictl_dir);

	return (ccd);
}

void
altera_sc_clear_status(void)
{
	int ccd;

	if ((ccd = open_berictl_dir(1)) == -1)
		return;

	unlinkat(ccd, SC_PID_FILE, 0);
	unlinkat(ccd, SC_PORT_FILE, 0);

	close(ccd);
}

int
altera_sc_get_status(pid_t *pidp, int *portp)
{
	int ccd, pidfd, portfd, port, ret;
	pid_t pid;
	char buf[8];

	if (pidp != NULL)
		*pidp = 0;
	if (portp != NULL)
		*portp = 0;

	ccd = pidfd = portfd = -1;
	ret = -1;

	if ((ccd = open_berictl_dir(1)) == -1)
		goto error;
	if ((pidfd = openat(ccd, SC_PID_FILE, O_RDONLY)) == -1)
		goto error;
	if (read(pidfd, buf, sizeof(buf)) < 1) {
		warn("failed to read %s", SC_PID_FILE);
		goto error;
	}
	if (!isdigit(buf[0])) {
		warnx("%s doesn't contain a number", SC_PID_FILE);
		goto error;
	}
	pid = strtol(buf, NULL, 10);

	if ((portfd = openat(ccd, SC_PORT_FILE, O_RDONLY)) == -1)
		goto error;
	if (read(portfd, buf, sizeof(buf)) < 1) {
		warn("failed to read %s", SC_PID_FILE);
		goto error;
	}
	if (!isdigit(buf[0])) {
		warnx("%s doesn't contain a number", SC_PORT_FILE);
		goto error;
	}
	port = strtol(buf, NULL, 10);

	/* Check that the process is actually running. */
	if (kill(pid, 0) == 0) {
		if (pidp != NULL)
			*pidp = pid;
		if (portp != NULL)
			*portp = port;
		ret = 0;
	}

error:
	close(ccd);
	close(pidfd);
	close(portfd);
	return (ret);
}

int
altera_sc_write_status(pid_t pid, int port)
{
	int ccd, pidfd, portfd, ret;

	ccd = pidfd = portfd = -1;
	ret = -1;

	if ((ccd = open_berictl_dir(0)) == -1)
		goto error;
	if ((pidfd = openat(ccd, SC_PID_FILE, O_WRONLY|O_CREAT|O_TRUNC,
	    S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH)) == -1) {
		warn("can't open %s", SC_PID_FILE);
		goto error;
	}
	if ((portfd = openat(ccd, SC_PORT_FILE, O_WRONLY|O_CREAT|O_TRUNC,
	    S_IRUSR|S_IWUSR|S_IRGRP|S_IWGRP|S_IROTH)) == -1) {
		warn("can't open %s", SC_PORT_FILE);
		goto error;
	}

	dprintf(pidfd, "%d\n", pid);
	dprintf(portfd, "%d\n", port);
	ret = 0;

error:
	close(ccd);
	close(pidfd);
	close(portfd);
	if (ret != 0)
		altera_sc_clear_status();
	return (ret);
}

/* end */
