%{
/*-
 * Copyright (c) 2012 Philip Paeps
 * Copyright (c) 2012 Robert N. M. Watson
 * Copyright (c) 2015 Alexandre Joannou
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

#include <assert.h>
#include <ctype.h>
#include <err.h>
#include <string.h>

#include "y.tab.h"

#define YY_NO_UNPUT
#define YY_NO_INPUT

extern int yyline;

struct keyword {
	const char *name;
	int value;
} keywords[] = {
	{ "addr",   KW_ADDR   },
	{ "class",  KW_CLASS  },
	{ "device", KW_DEVICE },
	{ "getenv", KW_GETENV },
	{ "ifdef",  KW_IFDEF  },
	{ "ifndef", KW_IFNDEF },
	{ "irq",    KW_IRQ    },
	{ "length", KW_LENGTH },
	{ "module", KW_MODULE },
	{ "option", KW_OPTION },
	{ 0, 0 },
};

unsigned int	dec(const char *);
unsigned int	hex(const char *);
int		keyword(const char *);
int		yyerror(const char *);

%}
ID	[A-Za-z_][-A-Za-z_0-9.]*
%%
{ID}		{
			int i;

			BEGIN 0;
			if ((i = keyword(yytext)) == -1) {
				yylval.str = strdup(yytext);
				return (ID);
			}
			return (i);
		}
\"[^"]+\"	{
			BEGIN 0;
			yytext[yyleng-1] = '\0';
			yylval.str = strdup(yytext + 1);
			return (NAME);
		}
0x[0-9a-fA-F]+	{
			yylval.str = strdup(yytext);
			return (NUMBER);
		}
[0-9]+		{
			yylval.str = strdup(yytext);
			return (NUMBER);
		}
;		{	return (SEMICOLON);		}
\{		{	return (OBRACE);		}
\}		{	return (EBRACE);		}
\n		{	yyline++;			}
#.*		{	; /* Ignored (comment). */	}
[ \t\f]*	{	; /* Ignored (whitespace). */	}
%%

int
keyword(const char *s)
{
	struct keyword *kw;

	for (kw = keywords; kw->name != 0; kw++)
		if (strcmp(s, kw->name) == 0)
			return (kw->value);
	return (-1);
}

unsigned int
dec(const char *s)
{
	unsigned int n;

	(void)sscanf(s, "%d", &n);
	return (n);
}

unsigned int
hex(const char *s)
{
	unsigned int n;

	(void)sscanf(s+2, "%x", &n);
	return (n);
}
