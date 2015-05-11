/*-
 * Copyright (c) 2013 SRI International
 * Copyright (c) 2013 Jonathan Anderson
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

int     altera_sc_start(pid_t *pidp, int *portp);
void    altera_sc_stop(pid_t pid);
void    altera_sc_clear_status(void);
int     altera_sc_get_status(pid_t *pidp, int *portp);
int     altera_sc_write_status(pid_t pid, int port);

/**
 * Different versions of Quartus II system-console use different formats
 * in response to commands.
 */
struct altera_syscons_parser
{
	/** A human-readable name for the protocol we parse. */
	const char *asp_name;

	/** Parse a raw response. */
	int (*parse_response)(const char *response, size_t len,
		const char **begin_out, const char **end_out);

	/**
	 * Parse a single "service path" (unique board identifier).
	 *
	 * @param  cable_pattern    a substring that uniquely identifies the
	 *                          board that we're interested in
	 */
	int (*parse_service_path)(const char *response, size_t len,
		const char *cable_pattern,
		const char **begin_out, const char **end_out);
};


struct altera_syscons_parser*	altera_choose_parser(const char *version);
struct altera_syscons_parser*	altera_get_v12_parser(void);
struct altera_syscons_parser*	altera_get_v13_parser(void);
