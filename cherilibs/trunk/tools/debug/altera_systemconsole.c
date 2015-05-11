/*-
 * Copyright (c) 2012-2013 Bjoern A. Zeeb
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Jonathan Anderson
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

#include <assert.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#include "altera_systemconsole.h"
#include "cheri_debug.h"
#include "cherictl.h"


struct altera_syscons_parser*
altera_choose_parser(const char *version)
{
	static const char v12[] = "return {12";
	static const char v13[] = "return \"13";

	if (strncmp(version, v12, sizeof(v12) - 1) == 0)
		return altera_get_v12_parser();

	/* v13 (and later?) will first return an inline comment. Ignore it. */
	if (version[0] == '#') {
		version = strchr(version, '\n');

		if (version == NULL) {
			fprintf(stderr, "Unterminated comment:\n'%s'\n",
			    version);
			return (NULL);
		}
		version++;
	}

	if (strncmp(version, v13, sizeof(v13) - 1) == 0)
		return altera_get_v13_parser();

	fprintf(stderr, "Unknown version string '%s'\n", version);
	return (NULL);
}


/**
 * Generic parser for device path strings.
 *
 * In both v12 and v13, device strings are formatted as:
 * "${begin}/path/to/dev1${end} ${begin}/path/to/dev2${end}"
 * for different values to ${begin} and ${end}.
 */
static int
parse_service_path(const char *buf, size_t buflen, const char *cable_pattern,
	const char *begin_delimiter, const char *end_delimiter,
	const char **begin, const char **end)
{
	size_t beginlen = strlen(begin_delimiter);
	const char *i;

	assert(buf != NULL);
	assert(begin != NULL);
	assert(end != NULL);

	const char *min = strstr(buf, begin_delimiter);

	if (min == NULL) {
		fprintf(stderr, "Device paths string missing "
		    "beginning delimiter '%s':\n'%s'\n", begin_delimiter, buf);
		return (BERI_DEBUG_ERROR_DATA_UNEXPECTED);
	}

	if (cable_pattern == NULL) {
		/*
		 * The cable pattern is only required if there are multiple
		 * cables attached to the system.
		 */
		const char *next_closing_brace = strstr(min, end_delimiter);
		if (next_closing_brace == NULL) {
			fprintf(stderr, "Device paths string missing "
			    " end delimiter '%s':\n'%s'\n", end_delimiter, buf);
			return (BERI_DEBUG_ERROR_DATA_UNEXPECTED);
		}

		if (strstr(next_closing_brace, begin_delimiter) != NULL) {
			fprintf(stderr, "Found multiple cables. "
			    "Use -c <cable> to select the right one.\n");
			return (BERI_DEBUG_USAGE_ERROR);
		}

		*begin = min + beginlen;
		*end = next_closing_brace;

		return (BERI_DEBUG_SUCCESS);
	}


	/*
	 * We have a cable pattern; find the path that corresponds to it.
	 */
	const char *match = strstr(min, cable_pattern);
	if (match == NULL) {
		fprintf(stderr, "No such cable '%s'\n", cable_pattern);
		return (BERI_DEBUG_ERROR_DATA_UNEXPECTED);
	}

	if (strstr(match + 1, cable_pattern) != NULL) {
		fprintf(stderr, "Ambiguous cable '%s'\n", cable_pattern);
		return (BERI_DEBUG_USAGE_ERROR);
	}

	assert(strstr(match, end_delimiter) != NULL);
	*end = strstr(match, end_delimiter);

	for (i = match; i >= min; i--) {
		if (strncmp(i, begin_delimiter, beginlen) == 0) {
			*begin = i + beginlen;
			return (BERI_DEBUG_SUCCESS);
		}
	}

	assert(0 && ("unable to find beginning delimiter,"
	             " but we have already confirmed its existence!"));

	return (BERI_DEBUG_USAGE_ERROR);
}

static int
altera_parse_q12_response(const char *buf, size_t buflen,
	const char **p, const char **q)
{

	static const char ERR_BEGIN[] = "error {";
	static const char ERR_END[] = "}\n";

	if (strncmp(buf, ERR_BEGIN, sizeof(ERR_BEGIN) - 1) == 0) {
		*p = buf + (sizeof(ERR_BEGIN) - 1);
		*q = strstr(buf, ERR_END);

		if (*q == NULL)
			*q = buf + strlen(buf);

		return (BERI_DEBUG_ERROR_ALTERA_SOFTWARE);
	}

	const char RETURN_OK[] = "return {";

	/* Make sure the first we got back was "return {" and not an error. */
	if (strncmp(RETURN_OK, buf, sizeof(RETURN_OK)-1) != 0) {
		fprintf(stderr, "Did not get \"return\" reply: '%s'\n", buf);
		return (BERI_DEBUG_ERROR_READ);
	}

	*q = strstr(buf, "}\n");
	if (*q == NULL) {
		return (BERI_DEBUG_ERROR_INCOMPLETE);
	}

	*p = strstr(buf, "{");
	if (*p == NULL) {
		fprintf(stderr, "no '{'\n");
		return (BERI_DEBUG_ERROR_READ);
	}
	(*p) += 1;

	return (BERI_DEBUG_SUCCESS);
}


static int
altera_parse_q12_service_path(const char *buf, size_t buflen, const char *cable,
	const char **begin, const char **end)
{

	return parse_service_path(buf, buflen, cable, "{", "}", begin, end);
}


struct altera_syscons_parser*
altera_get_v12_parser()
{
	static struct altera_syscons_parser v12_parser = {
		.asp_name = "Quartus II v12",
		.parse_response = altera_parse_q12_response,
		.parse_service_path = altera_parse_q12_service_path,
	};

	return &v12_parser;
}


static int
altera_parse_q13_response(const char *buffer, size_t len,
	const char **begin, const char **end)
{

	*begin = buffer;
	*end = strstr(buffer, "\n");
	if (*end == NULL) {
		return (BERI_DEBUG_ERROR_INCOMPLETE);
	}


	/*
	 * The first line of a system-console response might be a comment.
	 */
	while (**begin == '#') {
		/*
		 * Make a copy of the comment to dump to stderr.
		 *
		 * Don't dump it right away, since we might get called again
		 * with the same buffer if the current response is incomplete.
		 */
		const size_t comment_len = *end - buffer;
		char copy[comment_len];
		strncpy(copy, buffer, comment_len - 1);
		copy[comment_len - 1] = '\0';

		/*
		 * Find the end of the actual (non-comment) response line.
		 */
		*begin = *end + 1;
		*end = strstr(*begin, "\n");
		if (*end == NULL)
			return (BERI_DEBUG_ERROR_INCOMPLETE);

		/*
		 * We have a complete response; print the comment.
		 */
		fprintf(stderr, "%s\n", copy);
	}

	static const char BEGIN[] = "return \"";
	static const char ERR_BEGIN[] = "error \"";
	static const char END[] = "\"";

	if (strncmp(*begin, ERR_BEGIN, sizeof(ERR_BEGIN) - 1) == 0) {
		*begin += (sizeof(ERR_BEGIN) - 1);

		const char *err_end = *end - (sizeof(END) - 1);
		if (strncmp(err_end, END, sizeof(END) - 1) == 0)
			*end = err_end;

		return (BERI_DEBUG_ERROR_ALTERA_SOFTWARE);
	}

	if (strncmp(*begin, BEGIN, sizeof(BEGIN) - 1) != 0) {
		fprintf(stderr, "response did not begin with '%s':\n'%s'\n",
		        BEGIN, *begin);
		return (BERI_DEBUG_ERROR_DATA_UNEXPECTED);
	}

	*begin += (sizeof(BEGIN) - 1);
	*end -= (sizeof(END) - 1);
	assert(*end >= *begin);

	if (strncmp(*end, END, sizeof(END) - 1) != 0) {
		fprintf(stderr, "response did not end with '%s': '%s'\n",
		        END, *end);
		return (BERI_DEBUG_ERROR_DATA_UNEXPECTED);
	}

	return (BERI_DEBUG_SUCCESS);
}


static int
altera_parse_q13_service_path(const char *buf, size_t buflen, const char *cable,
	const char **begin, const char **end)
{

	return parse_service_path(buf, buflen, cable, "\\{", "\\}", begin, end);
}


struct altera_syscons_parser*
altera_get_v13_parser()
{
	static struct altera_syscons_parser v13_parser = {
		.asp_name = "Quartus II v13",
		.parse_response = altera_parse_q13_response,
		.parse_service_path = altera_parse_q13_service_path,
	};

	return &v13_parser;
}
