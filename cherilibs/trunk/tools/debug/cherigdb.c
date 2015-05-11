/*-
 * Copyright (c) 2011-2012 Philip Paeps
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

/*
 * CHERI GDB server stub.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>

#include <assert.h>
#include <errno.h>
#include <fcntl.h>
#include <setjmp.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include "../../include/cheri_debug.h"
#include "cherictl.h"
#include "gdb_int.h"

static const char *progname;
static int gdb_fd = -1;
static jmp_buf jmp_top;

struct beri_debug *bdp = NULL;
struct gdb_dbgport *gdb_cur = NULL;
int gdb_listening;


static void
usage(void)
{

	fprintf(stderr, "%s [-p path_to_socket] COMM\n", progname);
	fprintf(stderr, "\tCOMM may either be a tty device (for serial "
	    "debugging), or \n\tHOST:PORT to listen for a TCP connection.\n");
	exit(EXIT_FAILURE);
}

/*
 * Open a connection to the remote debugger.
 */
static void
dbgport_open(const char *path)
{
	struct sockaddr_in soa;
	struct termios tio;
	socklen_t soalen;
	char *port_str;
	int one, port, tmpfd;

	assert(path != NULL);
	if (!strchr(path, ':')) {
		gdb_fd = open(path, O_RDWR);
		if (gdb_fd < 0) {
			fprintf(stderr, "Couldn't open remote: %s\n",
			    strerror(errno));
			exit(EXIT_FAILURE);
		}
		tcgetattr(gdb_fd, &tio);
		tio.c_cflag &= ~(CSIZE | PARENB);
		tio.c_cflag |= CLOCAL | CS8;
		tio.c_cc[VMIN] = 1;
		tio.c_cc[VTIME] = 0;
		tio.c_iflag = 0;
		tio.c_lflag = 0;
		tio.c_oflag = 0;
		tcsetattr(gdb_fd, TCSANOW, &tio);
		fprintf(stderr, "Remote debugging using %s\n", path);
	} else {
		port_str = strchr(path, ':');
		port = atoi(port_str + 1);
		tmpfd = socket(PF_INET, SOCK_STREAM, 0);
		if (tmpfd < 0) {
			fprintf(stderr, "Couldn't open socket: %s\n",
			    strerror(errno));
			exit(EXIT_FAILURE);
		}
		one = 1;
		setsockopt(tmpfd, SOL_SOCKET, SO_REUSEADDR, (char *)&one,
		    sizeof(one));
		soa.sin_family = PF_INET;
		soa.sin_port = htons(port);
		/* Prevent accidents: bind to the loopback address only. */
		soa.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
		if (bind(tmpfd, (struct sockaddr *)&soa, sizeof(soa)) ||
		    listen(tmpfd, 1)) {
			fprintf(stderr, "Couldn't bind address: %s\n",
			    strerror(errno));
			exit(EXIT_FAILURE);
		}
		fprintf(stderr, "Listening on port %d\n", port);

		soalen = sizeof(soa);
		gdb_fd = accept(tmpfd, (struct sockaddr *)&soa, &soalen);
		if (gdb_fd == -1) {
			fprintf(stderr, "Couldn't accept connection: %s\n",
			    strerror(errno));
			exit(EXIT_FAILURE);
		}
		/* Send TCP keepalives. */
		one = 1;
		setsockopt(tmpfd, SOL_SOCKET, SO_KEEPALIVE, (char *)&one,
		    sizeof(one));
		/*
		 * The GDB protocol uses very small packets.  By defaut TCP
		 * likes to delay these.  Not doing so speeds things up quite
		 * a bit.
		 */
		one = 1;
		setsockopt(gdb_fd, IPPROTO_TCP, TCP_NODELAY, (char *)&one,
		    sizeof(one));
		close(tmpfd);
		/*
		 * Prevent the GDB session from falling over when the remote
		 * client disconnects -- this allows us to reconnect too.
		 */
		signal(SIGPIPE, SIG_IGN);

		fprintf(stderr, "Remote debugging from host %s\n",
		    inet_ntoa(soa.sin_addr));
	}
}

static void
dbgport_close(void)
{

	assert(gdb_fd != -1);
	close(gdb_fd);
}

int
main(int argc, char *argv[])
{
	const char *pathp;
	int opt, ret;

	if (setjmp(jmp_top)) {
		fprintf(stderr, "Exiting\n");
		exit(EXIT_FAILURE);
	}

	progname = argv[0];
	pathp = NULL;
	while ((opt = getopt(argc, argv, "p:")) != -1) {
		switch (opt) {
		case 'p':
			pathp = optarg;
			break;

		default:
			usage();
		}
	}
	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();

	if (pathp != NULL)
		ret = beri_debug_client_open_path(&bdp, pathp);
	else
		ret = beri_debug_client_open(&bdp);

	if (ret != BERI_DEBUG_SUCCESS) {
		fprintf(stderr, "Failure opening debugging session: %s\n",
		    beri_debug_strerror(ret));
		exit(EXIT_FAILURE);
	}

	for (;;) {
		dbgport_open(argv[0]);
		setjmp(jmp_top);

		gdb_listening = 0;
		gdb_tx_begin('T');

		dbgport_close();
	}

	beri_debug_client_close(bdp);
	exit(EXIT_SUCCESS);
}
