%{
/*-
 * Copyright (c) 2012 Philip Paeps
 * Copyright (c) 2012-2013 Robert N. M. Watson
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

#include <sys/queue.h>

#include <assert.h>
#include <ctype.h>
#include <dlfcn.h>
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "pismdev/pism.h"

const char *yyfile;
uint8_t yybusno;
int yyline;

static void	device_start(const char *name);
static void	device_finish(void);
static void	load_module(const char *path);
void		yyerror(const char *s);
int		yywrap(void);

static bool			 ifenv;
static struct pism_device	*curpd;
static struct pism_module	*curmod;

%}
%union {
	char *str;
	struct pism_device *pd;
}

%token OBRACE
%token EBRACE
%token SEMICOLON

%token KW_ADDR
%token KW_CLASS
%token KW_DEVICE
%token KW_GETENV
%token KW_IFDEF
%token KW_IFNDEF
%token KW_IRQ
%token KW_LENGTH
%token KW_MODULE
%token KW_OPTION
%token KW_PATH

%token	<str>	ID
%token	<str>	MODULE
%token	<str>	NAME
%token	<str>	NUMBER
%token	<str>	PATH

%type	<pd>	device_spec
%type	<pd>	param_list

%%
configuration:
	many_specs
		;

many_specs:
	many_specs spec
		|
	/* lambda */
		;

spec:
	module_spec
		|
	device_spec
		|
	ifdef_device_spec
		|
	ifndef_device_spec
		|
	SEMICOLON
		|
	error SEMICOLON
		;

module_spec:
	KW_MODULE PATH {
			load_module($2);
		}
		;

device_spec:
	KW_DEVICE NAME {
			ifenv = true;
			device_start($2);
		} OBRACE param_list EBRACE {
			device_finish();
		}
	;

ifdef_device_spec:
	KW_IFDEF NAME KW_DEVICE NAME {
			if (getenv($2) != NULL) {
				ifenv = true;
				device_start($4);
			} else
				ifenv = false;
		} OBRACE param_list EBRACE {
			if (ifenv)
				device_finish();
		}
	;

ifndef_device_spec:
	KW_IFNDEF NAME KW_DEVICE NAME {
			if (getenv($2) == NULL) {
				ifenv = true;
				device_start($4);
			} else
				ifenv = false;
		} OBRACE param_list EBRACE {
			if (ifenv)
				device_finish();
		}
	;

name:
	NAME
	| KW_GETENV NAME {
			const char *env;

			env = getenv($2);
			if (env == NULL)
				env = "";
			$<str>$ = strdup(env);
		}
	;

number:
	NUMBER
	| KW_GETENV NAME {
			const char *env;

			env = getenv($2);
			if (env == NULL)
				env = "";
			$<str>$ = strdup(env);
		}
	;

param_list:
	param
	| param_list param
	;

param:
	KW_ADDR number SEMICOLON {
			if (ifenv) {
				printf("%s: address %s\n", curpd->pd_name,
				    $<str>2);
				pism_device_option_add(curpd,
				    PISM_DEVICE_OPTION_ADDR, $<str>2);
			}
		}
		|
	KW_CLASS ID SEMICOLON {
			if (ifenv) {
				printf("%s: module %s\n", curpd->pd_name,
				    $<str>2);
				assert(curmod == NULL);
				curmod = curpd->pd_mod =
				    pism_module_lookup($<str>2);
				assert(curmod != NULL);
			}
		}
		|
	KW_IRQ number SEMICOLON {
			if (ifenv) {
				printf("%s: irq %s\n", curpd->pd_name,
				    $<str>2);
				pism_device_option_add(curpd,
				    PISM_DEVICE_OPTION_IRQ, $<str>2);
			}
		}
		|
	KW_LENGTH number SEMICOLON {
			if (ifenv) {
				printf("%s: length %s\n", curpd->pd_name,
				    $<str>2);
				pism_device_option_add(curpd,
				    PISM_DEVICE_OPTION_LENGTH, $<str>2);
			}
		}
		|
	KW_OPTION ID name SEMICOLON {
			if (ifenv) {
				printf("%s: option %s=%s\n", curpd->pd_name,
				    $2, $<str>3);
				pism_device_option_add(curpd, $2, $<str>3);
			}
		}
		;

%%

static void
load_module(const char *path)
{
	struct pism_module *pm;
	void *dlhdl;

	dlhdl = dlopen(path, RTLD_NOW);
	if (dlhdl == NULL)
		errx(4, "Unable to load module %s (%s)", path, dlerror());

	pm = (struct pism_module *)dlsym(dlhdl, "__pism_module_info");
	if (pm == NULL)
		errx(5, "Module %s does not define __pism_module_info", path);

	if (pism_module_lookup(pm->pm_name)) {
		printf("Already loaded module with name '%s', skipping.\n", 
			pm->pm_name);
		return;
	}

	pm->pm_path = path;
	pm->pm_initialised = false;

	SLIST_INSERT_HEAD(g_pism_modules, pm, pm_next);
	printf("Loaded module '%s' (%s)\n", pm->pm_path, pm->pm_name);
}

static void
device_start(const char *name)
{

	curmod = NULL;
	curpd = calloc(1, sizeof(*curpd));
	assert(curpd != NULL);
	curpd->pd_name = strdup(name);
	curpd->pd_busno = yybusno;
	TAILQ_INIT(&curpd->pd_options);
}

static void
device_finish(void)
{
	bool ret;

	assert(curpd != NULL);
	assert(curmod != NULL);
	ret = pism_device_options_finalise(curpd);
	if (curmod->pm_dev_init != NULL)
		curmod->pm_dev_init(curpd);
	SLIST_INSERT_HEAD(g_pism_devices[yybusno], curpd, pd_next);
	curpd = NULL;
	curmod = NULL;
}

void
yyerror(const char *s)
{

	errx(1, "%s:%d: %s", yyfile, yyline + 1, s);
}

int
yywrap(void)
{

	return (1);
}
