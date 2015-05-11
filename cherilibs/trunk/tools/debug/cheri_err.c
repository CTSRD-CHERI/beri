/*-
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2011-2013 Jonathan Woodruff
 * Copyright (c) 2012-2013 SRI International
 * Copyright (c) 2012 Simon W. Moore
 * Copyright (c) 2012 Robert Norton
 * Copyright (c) 2012-2013 Bjoern A. Zeeb
 *
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
#include <inttypes.h>

#include "cheri_debug.h"


const char *
beri_debug_strerror(int ret)
{

	switch (ret) {
	case BERI_DEBUG_SUCCESS:
		return ("success");

	case BERI_DEBUG_ERROR_SOCKET:
		return ("socket()");

	case BERI_DEBUG_ERROR_CONNECT:
		return ("connect()");

	case BERI_DEBUG_ERROR_SEND:
		return ("send()");

	case BERI_DEBUG_ERROR_BPBOUND:
		return ("breakpoint bounds error");

	case BERI_DEBUG_ERROR_REGBOUND:
		return ("register bounds error");

	case BERI_DEBUG_ERROR_IMMBOUND:
		return ("immediate value bounds error");

	case BERI_DEBUG_ERROR_DATA_UNEXPECTED:
		return ("unexpected data in reply");

	case BERI_DEBUG_ERROR_DATA_TOOBIG:
		return ("payload too big");

	case BERI_DEBUG_ERROR_ADDR_INVALID:
		return ("invalid address");

	case BERI_DEBUG_ERROR_UNSUPPORTED:
		return ("unsupported debug operation");

	case BERI_DEBUG_ERROR_EXCEPTION:
		return ("exception fired");

	case BERI_DEBUG_ERROR_NOBREAK:
		return ("breakpoint has not fired");

	case BERI_DEBUG_ERROR_OPEN:
		return ("open()");

	case BERI_DEBUG_ERROR_STAT:
		return ("stat()/fstat()");

	case BERI_DEBUG_ERROR_READ:
		return ("read()");

	case BERI_DEBUG_ERROR_SOCKETPAIR:
		return ("socketpair()");

	case BERI_DEBUG_ERROR_FORK:
		return ("fork()");

	case BERI_DEBUG_ERROR_MALLOC:
		return ("couldn't allocate memory");

	case BERI_DEBUG_ERROR_INVALID_TRACECOUNT:
		return ("invalid number of instructions to trace");

	case BERI_DEBUG_ERROR_NOTPAUSED:
		return ("pipeline not paused");

	case BERI_DEBUG_ERROR_WRONGRESPONSE:
		return ("Unexpected Response from HW");

	case BERI_DEBUG_ERROR_INCOMPLETE:
		return ("data stream is incomplete");

	case BERI_DEBUG_ERROR_ALTERA_SOFTWARE:
		return ("Altera tools returned an error");

	case BERI_DEBUG_ERROR_PCIEXPRESS_DISABLED:
		return ("berictl was built without PCI Express support");

	default:
		return ("unknown error");
	}
}
