/*-
 * Copyright (c) 2014 Ruslan Bukin
 *
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

#include <stdlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdio.h>
#include <stdint.h>
#include <unistd.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <time.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <arpa/inet.h>
#include <signal.h>
#include <sys/wait.h>
#include <termios.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/mdioctl.h>

int
attach_file(int fd, struct md_ioctl *mdio)
{
	struct stat st;
	int ret;

	if (stat(mdio->md_file, &st) < 0) {
		printf("cant stat file\n");
		return (1);
	}

	mdio->md_mediasize = st.st_size;

#if 0
	printf("filesize %ld bytes\n", st.st_size);
#endif
	ret = ioctl(fd, MDIOCATTACH, mdio);
	printf("result: %d\n", ret);

	return (0);
}

int
main(int argc, char *argv[])
{
	struct md_ioctl mdio;
	int fd;
	int opt;

	fd = open("/dev/beri_vtblk", O_RDWR);
	if (fd <= 0) {
		printf("Failed open character device\n");
		return (1);
	}

	while ((opt = getopt(argc, argv, "A:D")) != -1) {
		switch (opt) {
		case 'A':
			mdio.md_file = optarg;
			attach_file(fd, &mdio);
			break;
		case 'D':
			ioctl(fd, MDIOCDETACH, &mdio);
			break;
		default:
			break;
		}
	}

	return (0);
}
