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
#include <sys/mman.h>
#include <sys/select.h>
#include <time.h>
#include <pcie_stream.h>
#include <sys/poll.h>
#include <sys/ioctl.h>
#include "cheri_debug.h"
#include <sys/socket.h>
#include <sys/event.h>
#include <signal.h>
#include <pthread.h>

#define BUFFER_SIZE (4096)

int sockfd;
int filefd;

int
read_from_socket(void)
{
	uint8_t buffer[BUFFER_SIZE];
	struct timespec tmout;
	struct kevent change;
	struct kevent change1;
	struct kevent event;
	struct kevent event1;
	int tot_sent;
	int to_send;
	int kq, kq1;
	int ret;
	int amt;
	int res;

	tmout.tv_sec = 0;
	tmout.tv_nsec = 10000000;

	kq = kqueue();
	if (kq == -1)
		perror("kqueue");

	kq1 = kqueue();
	if (kq1 == -1)
		perror("kqueue");

	EV_SET(&change, sockfd, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, 0);
	EV_SET(&change1, filefd, EVFILT_WRITE, EV_ADD | EV_ENABLE, 0, 0, 0);

	while (1) {
		ret = kevent(kq, &change, 1, &event, 1, &tmout);

		if (ret < 0)
			return (1);

		if (ret == 0)
			continue;

		amt = recv(sockfd, buffer, BUFFER_SIZE, 0);
		if (amt < 0)
			return amt;

		tot_sent = 0;
		while (amt > 0) {
			ret = kevent(kq1, &change1, 1, &event1, 1, &tmout);
			if (ret < 0)
				return (1);
			if (ret == 0) {
				/* timeout */
				continue;
			}
			to_send = amt > event1.data ? event1.data : amt;
			res = write(filefd, buffer + tot_sent, to_send);
			amt -= res;
			tot_sent += res;
		}

	}
}

int
write_to_socket(int sockfd, int filefd)
{
	uint8_t buffer[BUFFER_SIZE];
	struct timespec tmout;
	struct kevent change;
	struct kevent change1;
	struct kevent event;
	struct kevent event1;
	uint16_t fill;
	int tot_sent;
	int kq, kq1;
	int to_send;
	int ret;
	int res;
	int amt;

	tmout.tv_sec = 0;
	tmout.tv_nsec = 10000000;

	kq = kqueue();
	if (kq == -1)
		perror("kqueue");

	kq1 = kqueue();
	if (kq1 == -1)
		perror("kqueue");

	EV_SET(&change, filefd, EVFILT_READ, EV_ADD | EV_ENABLE, 0, 0, 0);
	EV_SET(&change1, sockfd, EVFILT_WRITE, EV_ADD | EV_ENABLE, 0, 0, 0);

	while (1) {
		ret = kevent(kq, &change, 1, &event, 1, &tmout);
		if (ret < 0)
			return (1);
		if (ret == 0)
			continue;

		fill = event.data;
		if (fill == 0) {
			/* XXX seems not possible to be here */
			continue;
		};

		amt = read(filefd, buffer, fill);
		if (amt < 0)
			return amt;

		tot_sent = 0;
		while (amt > 0) {
			ret = kevent(kq1, &change1, 1, &event1, 1, &tmout);
			if (ret < 0)
				return (1);
			if (ret == 0) {
				/* timeout */
				continue;
			}

			to_send = amt > event1.data ? event1.data : amt;
			res = send(sockfd, buffer + tot_sent, to_send, 0);
			if (res < 0)
				return res;
			amt -= res;
			tot_sent += res;
		}
	}
}

void
pth_handler(void *arg)
{

	read_from_socket();
}

int
sockit_stream_start(int sfd, int ffd)
{
	pthread_t thread;

	sockfd = sfd;
	filefd = ffd;
	pthread_create(&thread, NULL, (void *)pth_handler, (void *)0);
	write_to_socket(sockfd, filefd);

	return (0);
}
