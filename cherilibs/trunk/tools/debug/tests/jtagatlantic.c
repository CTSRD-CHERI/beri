/*
 * Copyright (c) 2013 Jonathan Anderson
 * Copyright (c) 2015 A. Theodore Markettos
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

#include <sys/types.h>

#include <err.h>
#include <inttypes.h>
#include <stdio.h>
#include <string.h>

#include "CuTest.h"
#include "jtagatlantic.h"
#include "cheri_debug.h"

#if 0
static void 

static void
ChooseQuartusParser(CuTest *tc)
{
	struct altera_syscons_parser *v12 = altera_get_v12_parser();
	struct altera_syscons_parser *v13 = altera_get_v13_parser();
	struct altera_syscons_parser *parser;

	parser = altera_choose_parser("return {12.0sp1 422}");
	CuAssertPtrNotNull(tc, parser);
	CuAssertStrEquals(tc, v12->asp_name, parser->asp_name);

	parser = altera_choose_parser("return {12.1 177}");
	CuAssertPtrNotNull(tc, parser);
	CuAssertStrEquals(tc, v12->asp_name, parser->asp_name);

	parser = altera_choose_parser("return \"13.0 foo\"");
	CuAssertPtrNotNull(tc, parser);
	CuAssertStrEquals(tc, v13->asp_name, parser->asp_name);

	parser = altera_choose_parser(
	    "# this is an inline comment.\n"
	    "return \"13.0 foo\"");
	CuAssertPtrNotNull(tc, parser);
	CuAssertStrEquals(tc, v13->asp_name, parser->asp_name);

	parser = altera_choose_parser("FOO INVALID BAR");
	CuAssertPtrEquals(tc, NULL, parser);

	parser = altera_choose_parser("# unterminated comment");
	CuAssertPtrEquals(tc, NULL, parser);
}


static void
parse_response(CuTest *tc, struct altera_syscons_parser *parser,
	const char *input, const char *expected_result)
{
	CuAssertPtrNotNull(tc, parser);
	CuAssertPtrNotNull(tc, parser->parse_response);

	const char *begin, *end;
	int ret = parser->parse_response(input, strlen(input),
		&begin, &end);

	CuAssertIntEquals_Msg(tc, "parse error",
		BERI_DEBUG_SUCCESS, ret);

	CuAssertPtrNotNullMsg(tc, "parsed NULL 'begin'", begin);
	CuAssertPtrNotNullMsg(tc, "parsed NULL 'end'", end);
	CuAssert(tc, "begin > end", (begin <= end));

	char result[end - begin + 1];
	strncpy(result, begin, end - begin);
	result[end - begin] = '\0';

	CuAssertStrEquals_Msg(tc, "unexpected result",
		expected_result, result);
}


static void
check_path(CuTest *tc, struct altera_syscons_parser *parser,
	const char *input, const char *cable,
	int expected_result, const char *expected_path)
{
	const char *begin, *end;

	CuAssertPtrNotNull(tc, parser);
	CuAssertPtrNotNull(tc, parser->parse_service_path);

	int ret = parser->parse_service_path(input, strlen(input), cable,
		&begin, &end);

	CuAssertIntEquals_Msg(tc, cable, expected_result, ret);

	if (expected_result == BERI_DEBUG_SUCCESS) {
		CuAssertPtrNotNullMsg(tc, "parsed NULL 'begin'", begin);
		CuAssertPtrNotNullMsg(tc, "parsed NULL 'end'", end);
		CuAssert(tc, "begin > end", (begin <= end));

		char result[end - begin + 1];
		strncpy(result, begin, end - begin);
		result[end - begin] = '\0';

		CuAssertStrEquals_Msg(tc, "unexpected path",
			expected_path, result);
	}
}


#define PATH \
	"/devices/EP4SGX230(.|ES)@1#3-3.7/(link)/JTAG/" \
	"(110:132 v1 #0)/phy_0/master"

static const char* paths[] = {
"/devices/EP4SGX230(.|ES)@1#3-5.1.2/(link)/JTAG/(110:132 v1 #0)/phy_0/master",
"/devices/EP4SGX230(.|ES)@1#3-5.1.3/(link)/JTAG/(110:132 v1 #0)/phy_0/master",
"/devices/EP4SGX230(.|ES)@1#3-5.1.4/(link)/JTAG/(110:132 v1 #0)/phy_0/master",
"/devices/EP4SGX230(.|ES)@1#3-5.2.1/(link)/JTAG/(110:132 v1 #0)/phy_0/master",
"/devices/EP4SGX230(.|ES)@1#3-5.2.7/(link)/JTAG/(110:132 v1 #0)/phy_0/master",
"/devices/EP4SGX230(.|ES)@1#3-5.3/(link)/JTAG/(110:132 v1 #0)/phy_0/master",
"/devices/EP4SGX230(.|ES)@1#3-5.4/(link)/JTAG/(110:132 v1 #0)/phy_0/master",
};


static void
ParseQuartus12(CuTest *tc)
{
	struct altera_syscons_parser *parser = altera_get_v12_parser();

	// Quartus v12 uses raw newlines in its help string.
	#define HELP_STRING_V12 \
		"Get help on any of the following commands: \n" \
		"\n" \
		"add_help\n" \
		"add_service\n" \
		"alt_xcvr_custom_is_rx_locked_to_data\n" \
		"transceiver_reconfig_analog_set_tx_vodctrl\n" \
		"\n" \
		"by typing help <command name>"

	parse_response(tc, parser,
	    "return {{" PATH "}}\n\ntcl>\n", "{" PATH "}");
	parse_response(tc, parser,
	    "return {" HELP_STRING_V12 "}\n\ntcl>\n", HELP_STRING_V12);
}


static void
ParseDevPathV12(CuTest *tc)
{
	char buf[1024];
	struct altera_syscons_parser *parser = altera_get_v12_parser();
	size_t i, len = 0;
	int ret;

	ret = snprintf(buf + len, sizeof(buf) - len, "return {");
	CuAssert(tc, "buf too small", (ret > 0));

	for (i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
		ret = snprintf(buf + len, sizeof(buf) - len,
			"{%s} ", paths[i]);
		CuAssert(tc, "buf too small", (ret > 0));
		len += ret;
	}
	len--;  // drop last space

	ret = snprintf(buf + len, sizeof(buf) - len, "}\n\ntcl>\n");
	CuAssert(tc, "buf too small", (ret > 0));

	buf[len] = '\0';


	// It's ok to have a NULL cable specifier if we only have one path.
	check_path(tc, parser, "{" PATH "}", NULL, BERI_DEBUG_SUCCESS,
	               PATH);
	check_path(tc, parser, buf, NULL, BERI_DEBUG_USAGE_ERROR, NULL);

	// Try a couple of normal cable identifiers.
	check_path(tc, parser, buf, "5.1.2", BERI_DEBUG_SUCCESS, paths[0]);
	check_path(tc, parser, buf, "5.4", BERI_DEBUG_SUCCESS, paths[6]);

	// This device does not exist.
	check_path(tc, parser, buf, "5.9999",
		BERI_DEBUG_ERROR_DATA_UNEXPECTED, NULL);


	// This device pattern is ambiguous.
	check_path(tc, parser, buf, "5",
		BERI_DEBUG_USAGE_ERROR, NULL);
}


static void
ParseQuartus13(CuTest *tc)
{
	struct altera_syscons_parser *parser = altera_get_v13_parser();

	// Quartus v13 escapes newlines as the "\\n" string.
	#define HELP_STRING_V13 \
		"Get help on any of the following commands: \\n" \
		"\\n" \
		"add_help\\n" \
		"add_service\\n" \
		"alt_xcvr_custom_is_rx_locked_to_data\\n" \
		"transceiver_reconfig_analog_set_tx_vodctrl\\n" \
		"\\n" \
		"by typing help <command name>"

	parse_response(tc, parser,
	    "return \"{" PATH "}\"\n\ntcl>\n", "{" PATH "}");
	parse_response(tc, parser,
	    "return \"" HELP_STRING_V13 "\"\n\ntcl>\n", HELP_STRING_V13);
}


static void
ParseDevPathV13(CuTest *tc)
{
	char buf[1024];
	struct altera_syscons_parser *parser = altera_get_v13_parser();
	size_t i, len = 0;
	int ret;

	ret = snprintf(buf + len, sizeof(buf) - len, "return \"");
	CuAssert(tc, "buf too small", (ret > 0));

	for (i = 0; i < sizeof(paths) / sizeof(paths[0]); i++) {
		ret = snprintf(buf + len, sizeof(buf) - len,
			"\\{%s\\} ", paths[i]);
		CuAssert(tc, "buf too small", (ret > 0));
		len += ret;
	}
	len--;  // drop last space

	ret = snprintf(buf + len, sizeof(buf) - len, "\"\n\ntcl>\n");
	CuAssert(tc, "buf too small", (ret > 0));

	buf[len] = '\0';


	// It's ok to have a NULL cable specifier if we only have one path.
	check_path(tc, parser, "\\{/x\\}", NULL, BERI_DEBUG_SUCCESS, "/x");
	check_path(tc, parser, buf, NULL, BERI_DEBUG_USAGE_ERROR, NULL);

	// Try a couple of normal cable identifiers.
	check_path(tc, parser, buf, "5.1.2", BERI_DEBUG_SUCCESS, paths[0]);
	check_path(tc, parser, buf, "5.4", BERI_DEBUG_SUCCESS, paths[6]);

	// This device does not exist.
	check_path(tc, parser, buf, "5.9999",
		BERI_DEBUG_ERROR_DATA_UNEXPECTED, NULL);


	// This device pattern is ambiguous.
	check_path(tc, parser, buf, "5",
		BERI_DEBUG_USAGE_ERROR, NULL);
}
#endif


static void
CheckJTAGGetError(CuTest *tc)
{
	char jt_error[256];
	printf("Hello world JTAG!\n");
	JTAGATLANTIC *atlantic_link = jtagatlantic_open(
		"BOGUS", 2, 0, "berictl jtag atlantic test");
	printf("atlantic_open = %p\n", atlantic_link);
	CuAssert(tc, "jtagatlantic_open() succeeded on garbage parameters", (atlantic_link == NULL));

	fprintf(stdout,"%s\n",beri_jtagatlantic_geterror(jt_error, sizeof(jt_error)));
	CuAssert(tc, "jtagatlantic_open() returned error other than 'Cable not available'", (strcmp(jt_error,"Cable not available")==0));
}


CuSuite* JTAGAtlanticSuite()
{
	CuSuite* suite = CuSuiteNew();

	SUITE_ADD_TEST(suite, CheckJTAGGetError);

	return suite;
}
