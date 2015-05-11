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
#include <stdint.h>
#include <unistd.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <string.h>
#include <time.h>
#include <sys/types.h>
#include <termios.h>
#include <fcntl.h>
#include <sys/event.h>

#define BUFFER_SIZE (4096)

int main(int argc, char *argv[])
{
	static struct termios term;
	struct timespec tmout;
	struct kevent change;
	struct kevent event;
	char *buffer[BUFFER_SIZE];
	int fill;
	char ch;
	int pid;
	int amt;
	int ret;
	int fd;
	int kq;

	tmout.tv_sec = 0;
	tmout.tv_nsec = 10000000;

	fd = open("/dev/beri_console", O_RDWR);
	if (fd == -1)
		perror("open failed");

	kq = kqueue();
	if (kq == -1)
		perror("kqueue");

	EV_SET(&change, fd, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, 0);

	pid = fork();
	if (pid > 0) {
		while (1) {
			ret = kevent(kq, &change, 1, &event, 1, &tmout);
			if (ret < 0)
				return (1);
			if (ret == 0)
				continue;

			fill = event.data;

	    		amt = read(fd, buffer, fill);
	    		write(fileno(stdout), buffer, amt);
        	}
	} else {
		tcgetattr(0, &term);
		term.c_lflag &= ~ICANON;
		term.c_lflag &= ~ECHO;
		tcsetattr(0, TCSANOW, &term);

		while (1) {
			ch = getchar();
			write(fd, &ch, 1);
		}
	}

	close(fd);

	return (0);
}
