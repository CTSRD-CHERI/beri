/*-
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Jonathan Woodruff
 * Copyright (c) 2013-2014 Jonathan Anderson
 * Copyright (c) 2013-2014 SRI International
 * Copyright (c) 2016 A. Theodore Markettos
 * Copyright (c) 2016 Alexandre Joannou
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

#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <sysexits.h>
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
	DIR *dir = opendir(".");
	struct dirent *file;
	char *dirname;
	int links = 0, fixed = 0;

	while ((file = readdir(dir)) != NULL)
	{
		char target[1024];
		ssize_t index =
			readlink(file->d_name, target, sizeof(target) - 1);

		if (index < 0) {
			// Not a symlink?
			if (errno == EINVAL)
				continue;

			err(EX_OSERR, "error in readlink('%s')", file->d_name);
		}

		links++;

		// Fix absolute paths.
		if (target[0] == '/') {
			target[index] = 0;

			char *newName;
			asprintf(&newName, "../..%s", target);

			if (unlink(file->d_name))
				err(EX_OSERR, "Failed to remove old link");

			if (symlink(newName, file->d_name))
				err(EX_OSERR, "Failed to create link");

			free(newName);
			fixed++;
		}
	}
	closedir(dir);

	if (links == 0)
		errx(EX_USAGE, "no symbolic links in %s", getwd(NULL));

	printf("fixed %d/%d symbolic links\n", fixed, links);
}
