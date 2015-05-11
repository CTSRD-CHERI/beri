/*-
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2011-2013 Jonathan Woodruff
 * Copyright (c) 2012-2013 SRI International
 * Copyright (c) 2012-2013 Robert Nortion
 * Copyright (c) 2012-2014 Bjoern A. Zeeb
 * Copyright (c) 2013 David T. Chisnall
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

/*
 * Simple BERI debug tool: various debugging operations can be exercised from
 * the command line, including inspecting register state, pausing, resuming,
 * and single-stepping the processor.
 */

#include <sys/types.h>
#include <sys/socket.h>
#include <sys/un.h>

#include <assert.h>
#include <err.h>
#include <inttypes.h>
#include <limits.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

#include "../../include/cheri_debug.h"
#include "cherictl.h"

struct beri_debug *bdp;

static void
close_bdp(void)
{

	if (bdp != NULL)
		beri_debug_client_close(bdp);
}

static void
usage(void)
{

#ifdef BERI_NETFPGA
	fprintf(stderr, "cherictl [-nNqw] [-a addr] [-p path_to_socket|port] "
#else
	fprintf(stderr, "cherictl [-qw] [-a addr] [-p path_to_socket|port] "
#endif
	    "[-c cable] [-r regnum] [-v value]\n"
	    "    [-f filename] command\n"
	    "\tbreakpoint\tset breakpoint at adddr (-w to wait on it)\n"
	    "\tboot\ttell miniboot to proceed to the next kernel/loader\n"
	    "\tcleanup\tclean up external processes and files\n"
	    "\tc0regs\tlist CP0 registers\n"
	    "\tc2regs*\tlist capability registers\n"
	    "\tconsole\tconnect to BERI PISM UART at filename\n"
	    "\tdrain\tdrain debug socket\n"
	    "\tdumpatse\tdump all atse(4) MAC control registers in one go\n"
	    "\tdumpfifo\tdump fifo status and meta data\n"
	    "\tdumppic\tdump PIC status\n"
	    "\tlbu\tload unsigned byte from addr\n"
	    "\tld\tload double word from addr\n"
	    "\tlh\tload half word from addr\n"
	    "\tlhu\tload unsigned half word from addr\n"
	    "\tloadbin\tload binary file into cheri memory (deprecated)\n"
	    "\tloaddram\tload binary file into DE4 memory\n"
	    "\tloadsof\tload SOF format FPGA image to FPGA\n"
	    "\tlwu\tload unsigned word from addr\n"
	    "\tpause\tpause execution\n"
	    "\tpc\tprint PC\n"
	    "\tregs\tlist general-purpose registers\n"
	    "\treset\treset the processor\n"
	    "\tresume\tresume execution fully pipelined\n"
	    "\tsb\tstore byte value at addr\n"
	    "\tsd\tstore double word value at addr\n"
	    "\tsetpc\tset PC to addr\n"
	    "\tsetreg\tstore value in general-purpose regnum\n"
	    "\tsettracefilter\tset a filter for trace records from stream_trace_filter.config\n"
	    "\tsh\tstore half word value at addr\n"
	    "\tstep\tsingle-step execution\n"
	    "\tstreamtrace\treceive a stream of trace data, use -w for long stream\n"
	    "\tsw\tstore word value at addr\n"
	    "\tunpipeline\tresume execution unpipelined\n"
	    "\tmemtrace\ttrace the execution of some number of instructions\n");
	printf("\n");
	printf("\t* has side effects on software execution\n");
	exit(EXIT_FAILURE);
}

int
main(int argc, char *argv[])
{
	const char *addrp, *cablep, *filep, *pathp, *real_filep, *regnump, *valuep;
	int opt, ret, waitflag, zflag, binary;
	uint32_t oflags;

	bdp = NULL;

	addrp = NULL;
	binary = 0;
	cablep = NULL;
	filep = NULL;
	pathp = NULL;
	regnump = NULL;
	valuep = NULL;
	waitflag = 0;
	zflag = 0;
	oflags = BERI_DEBUG_CLIENT_OPEN_FLAGS_SOCKET;

	fprintf(stderr,
"\n"
"******************************* NOTICE *******************************\n"
"**                                                                  **\n"
"**      The cherictl command is DEPRECATED in favor of berictl!     **\n"
"**                                                                  **\n"
"**  If you are using cherictl because berictl isn't working please  **\n"
"**                 FIX or REPORT the issue promptly.                **\n"
"**                                                                  **\n"
"******************************* NOTICE *******************************\n"
"\n"
	);

	while ((opt = getopt(argc, argv, "2a:bc:f:Nnp:r:v:qwz")) != -1) {
		switch (opt) {
		case '2':
			oflags |= BERI_DEBUG_CLIENT_OPEN_FLAGS_BERI2;
			break;
		case 'a':
			addrp = optarg;
			break;

		case 'b':
			binary = 1;
			break;

		case 'c':
			cablep = optarg;
			break;

		case 'f':
			filep = optarg;
			break;

		case 'n':
#ifdef BERI_NETFPGA
			oflags |= BERI_DEBUG_CLIENT_OPEN_FLAGS_NETFPGA;
#else
			usage();
#endif
			break;

		case 'N':
			oflags |= BERI_DEBUG_CLIENT_OPEN_FLAGS_NO_PAUSE_RESUME;
			break;

		case 'p':
			pathp = optarg;
			break;

		case 'q':
			quietflag++;
			break;

		case 'r':
			regnump = optarg;
			break;

		case 'v':
			valuep = optarg;
			break;

		case 'w':
			waitflag++;
			break;

		case 'z':
			zflag++;
			break;

		default:
			usage();
		}
	}

	argc -= optind;
	argv += optind;
	if (argc != 1)
		usage();

	if (filep != NULL) {
		if ((real_filep = realpath(filep, NULL)) == NULL)
			err(1, "realpath(%s)", filep);
		filep = real_filep;
		if (zflag) {
			if ((filep = extract_file(filep, strcmp(argv[0],
			    "loadsof") == 0 ? ".sof" : "")) == NULL)
				errx(1, "failed to extract input file");
		}
	}

	if (strcmp(argv[0], "cleanup") == 0)
		ret = beri_debug_cleanup();
	else if (strcmp(argv[0], "console") == 0)
		ret = berictl_console(NULL, filep, cablep);
	else if (strcmp(argv[0], "loadsof") == 0)
		ret = berictl_loadsof(filep, cablep);
	else {
		if (pathp != NULL)
			ret = beri_debug_client_open_path(&bdp, pathp, oflags);
		else
			ret = beri_debug_client_open(&bdp, oflags);
		if (ret != BERI_DEBUG_SUCCESS) {
			if (strcmp(argv[0], "loaddram") == 0)
				ret = beri_debug_client_open_sc(&bdp, oflags);
			else
				ret = beri_debug_client_open_nios(&bdp,
				    cablep, oflags);
		}
		atexit(close_bdp);
		if (ret != BERI_DEBUG_SUCCESS) {
			fprintf(stderr,
			    "Failure opening debugging session: %s\n",
			    beri_debug_strerror(ret));
			exit(EXIT_FAILURE);
		}
		if (strcmp(argv[0], "breakpoint") == 0)
			ret = berictl_breakpoint(bdp, addrp, waitflag);
		else if (strcmp(argv[0], "boot") == 0)
			ret = berictl_setreg(bdp, "13", "0");
		else if (strcmp(argv[0], "c0regs") == 0)
			ret = berictl_c0regs(bdp);
		else if (strcmp(argv[0], "drain") == 0)
			ret = berictl_drain(bdp);
		else if (strcmp(argv[0], "dumpatse") == 0)
			ret = berictl_dumpatse(bdp, addrp);
		else if (strcmp(argv[0], "dumpfifo") == 0)
			ret = berictl_dumpfifo(bdp, addrp);
		else if (strcmp(argv[0], "dumppic") == 0)
			ret = berictl_dumppic(bdp);
		else if (strcmp(argv[0], "loadbin") == 0)
			ret = berictl_loadbin(bdp, addrp, filep);
		else if (strcmp(argv[0], "loaddram") == 0)
			ret = berictl_loaddram(bdp, addrp, filep, cablep);
		else if (strcmp(argv[0], "lbu") == 0)
			ret = berictl_lbu(bdp, addrp);
		else if (strcmp(argv[0], "lhu") == 0)
			ret = berictl_lhu(bdp, addrp);
		else if (strcmp(argv[0], "lwu") == 0)
			ret = berictl_lwu(bdp, addrp);
		else if (strcmp(argv[0], "ld") == 0)
			ret = berictl_ld(bdp, addrp);
		else if (strcmp(argv[0], "pause") == 0)
			ret = berictl_pause(bdp);
		else if (strcmp(argv[0], "pc") == 0)
			ret = berictl_pc(bdp);
		else if (strcmp(argv[0], "regs") == 0)
			ret = berictl_regs(bdp);
		else if (strcmp(argv[0], "reset") == 0)
			ret = berictl_reset(bdp);
		else if (strcmp(argv[0], "c2regs") == 0)
			ret = berictl_c2regs(bdp);
		else if (strcmp(argv[0], "resume") == 0)
			ret = berictl_resume(bdp);
		else if (strcmp(argv[0], "sb") == 0)
			ret = berictl_sb(bdp, addrp, valuep);
		else if (strcmp(argv[0], "sh") == 0)
			ret = berictl_sh(bdp, addrp, valuep);
		else if (strcmp(argv[0], "sw") == 0)
			ret = berictl_sw(bdp, addrp, valuep);
		else if (strcmp(argv[0], "sd") == 0)
			ret = berictl_sd(bdp, addrp, valuep);
		else if (strcmp(argv[0], "setpc") == 0)
			ret = berictl_setpc(bdp, addrp);
		else if (strcmp(argv[0], "setreg") == 0)
			ret = berictl_setreg(bdp, regnump, valuep);
		else if (strcmp(argv[0], "step") == 0)
			ret = berictl_step(bdp);
		else if (strcmp(argv[0], "streamtrace") == 0) {
			int streamTimes = 4;
			if (waitflag) streamTimes = 256;
			ret = berictl_stream_trace(bdp, streamTimes, binary);
		}
		else if (strcmp(argv[0], "settracefilter") == 0)
			ret = berictl_set_trace_filter(bdp);
		else if (strcmp(argv[0], "test") == 0) {
			berictl_pause(bdp);
			char test_base[20] = "0000000040000000";
			berictl_pause(bdp);
			berictl_loadbin(bdp, test_base, filep);
			berictl_reset(bdp);
			berictl_test_run(bdp);
			berictl_test_report(bdp);
			berictl_pause(bdp);
			char loopFile[32] = "obj/test_raw_template.mem";
			berictl_loadbin(bdp, test_base, loopFile);
			ret = BERI_DEBUG_SUCCESS;
		}
		else if (strcmp(argv[0], "unpipeline") == 0)
			ret = berictl_unpipeline(bdp);
		else if (strcmp(argv[0], "memtrace") == 0)
			ret = berictl_mem_trace(bdp, valuep);
		else
			ret = BERI_DEBUG_USAGE_ERROR;
	}

	if (ret == BERI_DEBUG_USAGE_ERROR)
		usage();

	if (ret != BERI_DEBUG_SUCCESS) {
		fprintf(stderr, "Failure applying operation: %s\n",
		    beri_debug_strerror(ret));
		exit(EXIT_FAILURE);
	}
	exit(EXIT_SUCCESS);
}
