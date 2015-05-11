/*-
 * Copyright (c) 2014 Lawrence Esswood
 * Copyright (c) 2014 Alex Horsman
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
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <inttypes.h>
#include "circular_buffer.h"

#define MIN(X,Y) ((X) < (Y) ? (X) : (Y))

circular_buffer*
circular_buffer_new()
{
	circular_buffer* buf = malloc(sizeof(circular_buffer));
	buf->in = 0;
	buf->out = 0;
	buf->buffer = malloc(CIRCULAR_BUFFER_SIZE);
	return buf;
}

void
circular_buffer_destroy(circular_buffer* buf)
{
	free(buf->buffer);
	free(buf);
}

ssize_t
circular_buffer_get_fill(circular_buffer *buf)
{
	return (buf->in - buf->out + CIRCULAR_BUFFER_SIZE) % CIRCULAR_BUFFER_SIZE;
}

ssize_t
circular_buffer_get_space(circular_buffer *buf)
{
	return CIRCULAR_BUFFER_SIZE - circular_buffer_get_fill(buf) - 1;
}

ssize_t
circular_buffer_flush(int sockfd, circular_buffer *out)
{
	ssize_t fill = circular_buffer_get_fill(out);
	while(fill != 0) {
		ssize_t copyAmount = MIN(CIRCULAR_BUFFER_SIZE - out->out, fill);

		ssize_t res = send(sockfd, out->buffer + out->out, copyAmount, 0);

		if(res < 0)
			return res;
		if (res == 0)
			return 0;

		out->out = (out->out + res) % CIRCULAR_BUFFER_SIZE;
		fill = circular_buffer_get_fill(out);
	}

	return 0;
}

void
circular_buffer_reset(circular_buffer *in, circular_buffer *out)
{
	out->in = 0;
	out->out = 0;
	in->in = 0;
	in->out = 0;
}

//TODO pay more attention to the flags
ssize_t
circular_buffer_recv(int sockfd, void *dest_buf, size_t len, int flags,
    circular_buffer* in, circular_buffer* out)
{
	ssize_t ret;

	ssize_t fill = circular_buffer_get_fill(in);
	ssize_t space = circular_buffer_get_space(in);
	ssize_t span;

	while (len > fill) {
		span = CIRCULAR_BUFFER_SIZE - in->in;
		if(out->in != out->out) {
			ret = circular_buffer_flush(sockfd, out);
			if (ret < 0)
				return ret;
		}

		ssize_t copyAmount = MIN(span, space);
		ssize_t amt = recv(sockfd, (in->buffer + in->in), copyAmount, 0);

		if(amt < 0)
			return amt;

		in->in = (in->in + amt) % CIRCULAR_BUFFER_SIZE;

		fill = circular_buffer_get_fill(in);
		space = circular_buffer_get_space(in);
	}

	ssize_t copied = 0;
	while(copied != len) {
		ssize_t copyAmount = MIN(CIRCULAR_BUFFER_SIZE - in->out, len - copied);
		memcpy(dest_buf + copied, in->buffer + in->out, copyAmount);

		in->out = (in->out + copyAmount) % CIRCULAR_BUFFER_SIZE;
		copied += copyAmount;
	}

	return copied;
}

ssize_t
circular_buffer_send(int sockfd, const void *source_buf, size_t len,
    int flags, circular_buffer* out)
{
	ssize_t space = circular_buffer_get_space(out);

	ssize_t ret;
	if(len > space) {
		ret = circular_buffer_flush(sockfd, out);
		if (ret < 0)
			return ret;
	}

	space = circular_buffer_get_space(out);

	if(len > space)
		return ret;

	ssize_t copied = 0;
	while(copied != len) {
		ssize_t copyAmount = MIN(CIRCULAR_BUFFER_SIZE - out->in, len - copied);
		memcpy(out->buffer + out->in, source_buf + copied, copyAmount);

		out->in = (out->in + copyAmount) % CIRCULAR_BUFFER_SIZE;
		copied += copyAmount;
	}

	return copied;
}
