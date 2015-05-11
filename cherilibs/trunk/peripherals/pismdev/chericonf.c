/*-
 * Copyright (c) 2012 Philip Paeps
 * Copyright (c) 2012 Robert N. M. Watson
 * Copyright (c) 2013 Colin Rothwell
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

#include <assert.h>
#include <dlfcn.h>
#include <err.h>
#include <stdio.h>
#include <stdlib.h>

#include "pismdev/pism.h"
#include "y.tab.h"

int yydebug = 1;
extern const char *yyfile;
extern FILE *yyin;
extern uint8_t yybusno;
extern int yyparse(void);

int
main(int argc, char **argv)
{
	struct pism_module *pm;

	if (argc != 2)
		errx(1, "Usage: chericonf filename");
	yyfile = argv[1];
	if ((yyin = fopen(yyfile, "r")) == NULL)
		err(2, "%s", yyfile);

	SLIST_INIT(g_pism_modules);

	if (yyparse())
		exit(3);

	printf("Loaded modules: ");
	SLIST_FOREACH(pm, g_pism_modules, pm_next) {
		printf("%s", pm->pm_path);
		printf(" ");
	}
	printf("\n");

	return (0);
}
