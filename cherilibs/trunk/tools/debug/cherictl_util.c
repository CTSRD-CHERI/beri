/*-
 * Copyright (c) 2013 SRI International
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

#define _GNU_SOURCE 

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/stat.h>

#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "../../include/cheri_debug.h"
#include "cherictl.h"
#include "eav.h"

char *tmpfilep;

static void
unlink_tmpfile(void)
{

	if (tmpfilep != NULL)
		unlink(tmpfilep);
}

static ssize_t
writeall(int fd, const char *buf, size_t len)
{
        size_t wlen = 0;
        ssize_t n;

        while (wlen != len) {
                /* XXX: a progress meter would require smaller writes */
                n = write(fd, buf + wlen, len - wlen);
                if (n < 0) {
                        /* XXX: would be polite to use select/poll here */
                        if (errno != EAGAIN && errno != EINTR)
                                return (n);
                } else
                        wlen += n;
        }

        return(len);
}

char *
extract_file(const char *filep, const char *suffix)
{
	int fd;
	size_t olen;
	unsigned char *ibuf, *obuf;
	enum eav_error eav_ret;
	enum eav_compression ctype;
	const char *tmpdir;
	struct stat sb;

	if ((fd = open(filep, O_RDONLY)) == -1)
		warn("open(%s)", filep);
	if (fstat(fd, &sb) == -1)
		warn("fstat(%s)", filep);
	if ((ibuf = mmap(NULL, sb.st_size, PROT_READ,
	    MAP_PRIVATE, fd, 0)) == MAP_FAILED)
		warn("mmap(%s)", filep);
	close(fd);
	
	ctype = eav_taste(ibuf, sb.st_size);
	eav_ret = extract_and_verify(ibuf, sb.st_size, &obuf, &olen,
	     1, ctype, EAV_DIGEST_NONE, NULL);
	munmap(ibuf, sb.st_size);
	if (eav_ret != EAV_SUCCESS) {
		warnx("extract error: %s", eav_strerror(eav_ret));
		return (NULL);
	}

	if ((tmpdir = getenv("TMPDIR")) == NULL)
		tmpdir = "/tmp";
	asprintf(&tmpfilep, "%s/berictl.XXXXXX%s", tmpdir, suffix);
	if ((fd = mkstemps(tmpfilep, strlen(suffix))) == -1)
		warn("mkstemp(%s)", tmpfilep);
	atexit(unlink_tmpfile);
	if (writeall(fd, (char *)obuf, olen) != olen)
		warn("writeall(%s)", tmpfilep);
	close(fd);

	return (tmpfilep);
}
