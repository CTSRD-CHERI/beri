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

#define CIRCULAR_BUFFER_SIZE (128 * 1024)

typedef struct {
	uint8_t *buffer;
	ssize_t in;
	ssize_t out;
} circular_buffer;

circular_buffer* circular_buffer_new();
void circular_buffer_destroy(circular_buffer* buf);

void circular_buffer_reset(circular_buffer *in, circular_buffer *out);
ssize_t circular_buffer_recv(int sockfd, void *dest_buf, size_t len,
    int flags, circular_buffer* in, circular_buffer* out);
ssize_t circular_buffer_send(int sockfd, const void *buf, size_t len,
    int flags, circular_buffer* out);