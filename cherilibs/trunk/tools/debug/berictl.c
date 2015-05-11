/*-
 * Copyright (c) 2011-2014 Robert N. M. Watson
 * Copyright (c) 2011-2013 Jonathan Woodruff
 * Copyright (c) 2012-2014 SRI International
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

/* Required for asprintf definition */
#define _GNU_SOURCE

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

/* GLibC requires that getopt strings start with + to obey POSIX */
#ifdef __linux__
#define	_GETOPT_PLUS	"+"
#else
#define _GETOPT_PLUS
#endif

#define CHERI_SUPPORT

extern char *which(char *filename);

struct subcommand;
typedef int (command_func)(struct subcommand *, int, char **);
typedef void (usage_func)(struct subcommand *);

struct subcommand {
	const char	*sc_name;	/* Command name */
	const char	*sc_argsummary; /* Summary of options and arguments */
	const char	*sc_desc;	/* Description */
	const char	*sc_getoptstr;	/* getopt() string */
	int		sc_minargs;	/* Number of arguments required */
	int		sc_maxargs;	/* Maximum number of arguments */
	usage_func	*sc_usage;	/* Usage printer */
	command_func	*sc_command;	/* Parse remaing args and run command */
	int		sc_flags;	/* flags */
};

#define SC_FLAG_HIDDEN	0x01

#define	SC_DECLARE_END \
    { NULL, NULL, NULL, NULL, 0, 0, NULL, NULL, 0 }
#define SC_DECLARE_HEADER(description) \
    { NULL, NULL, (description), NULL, 0, 0, NULL, NULL, 0 }
#define SC_DECLARE_NARGS(name, summary, description, n, func) \
    { (name), (summary), (description), NULL,(n), (n), generic_usage, (func), 0 }
#define SC_DECLARE_ZEROARGS(name, description, func) \
    { (name), NULL, (description), NULL, 0, 0, generic_usage, (func), 0 }

#define SC_IS_COMMAND(scp)	(scp->sc_name != NULL)
#define	SC_IS_END(scp)		(scp->sc_desc == NULL)
#define	SC_IS_HIDDEN(scp)	(scp->sc_flags & SC_FLAG_HIDDEN)
#define	SC_IS_HEADER(scp) \
    (scp->sc_name == NULL && scp->sc_desc != NULL)

static void	generic_usage(struct subcommand *);
static int	help_command(struct subcommand *, int, char **);
static void	help_usage(struct subcommand *);
static void	loadfile_usage(struct subcommand *);
static void	loadsof_usage(struct subcommand *);

static int	run_boot(struct subcommand *, int, char **);
static int	run_console(struct subcommand *, int, char **);
static int	run_dumpdevice(struct subcommand *, int, char **);
static int	run_load(struct subcommand *, int, char **);
static int	run_loadfile(struct subcommand *, int, char **);
static int	run_man(struct subcommand *, int, char **);
static int	run_setaddr(struct subcommand *, int, char **);
static int	run_store(struct subcommand *, int, char **);
static int	run_trace(struct subcommand *, int, char **);
static int	run_zeroargs(struct subcommand *, int, char **);

struct subcommand berictl_commands[] = {
	SC_DECLARE_HEADER("Hardware/Simulator access and control"),
	SC_DECLARE_ZEROARGS("boot",
	    "tell miniboot to proceed to the next kernel/loader", run_boot),
	SC_DECLARE_ZEROARGS("cleanup", "clean up external processes and files",
	    run_zeroargs),
	/* XXX Altera mode should take an instance */
	SC_DECLARE_ZEROARGS("console",
#ifdef BERI_NETFPGA
	    "connect to \"UART\" console (PISM via -s, NetFPGA via -n)",
#else
	    "connect to BERI PISM UART (via -s) or Altera UART",
#endif
	    run_console),
	SC_DECLARE_ZEROARGS("drain", "drain the debug socket", run_zeroargs),
	{
		"loadbin", "[-z] <file> <address>",
		"load binary file at address",
		"z", 2, 2, loadfile_usage, run_loadfile, 0
	},
	{ /* XXX: Altera specific */
		"loaddram", "[-z] <file> <address>",
		"load binary file at address",
		"z", 2, 2, loadfile_usage, run_loadfile, 0
	},
	{ /* XXX: Altera specific */
		"loadsof", "[-z] <file>",
		"Program FPGA with SOF format file",
		"z", 1, 1, loadsof_usage, run_loadfile, 0
	},

	SC_DECLARE_HEADER("Status"),
	SC_DECLARE_ZEROARGS("pc", "print program counter", run_zeroargs),
	SC_DECLARE_ZEROARGS("regs", "list general-purpose register contents",
	    run_zeroargs),
	SC_DECLARE_ZEROARGS("c0regs", "list CP0 register contents",
	   run_zeroargs),
#ifdef CHERI_SUPPORT
	SC_DECLARE_ZEROARGS("c2regs",
	    "list CP2 (capability) register contents (has side effects)",
	    run_zeroargs),
#endif

	SC_DECLARE_HEADER("Execution control"),
	{
		"breakpoint", "[-w] <addr>",
		"set breakpoint at address",
		"w", 1, 1, generic_usage, run_setaddr, 0
	},
	SC_DECLARE_ZEROARGS("pause", "pause execution", run_zeroargs),
	SC_DECLARE_ZEROARGS("reset", "reset processor", run_zeroargs),
	{
		"resume", "[-u]",
		"resume execution (optionally unpipelined)",
		"u", 0, 0, generic_usage, run_zeroargs, 0
	},
	SC_DECLARE_ZEROARGS("step", "single-step execution", run_zeroargs),
	SC_DECLARE_NARGS("setpc", "<address>",
	    "set the program counter to address", 1, run_setaddr),
	SC_DECLARE_NARGS("setreg", "<register> <value>",
	    "register to value", 2, run_setaddr),
	SC_DECLARE_NARGS("setthread", "<thread id>",
	    "set the thread to debug", 1, run_setaddr),

	SC_DECLARE_HEADER("Memory access"),
	SC_DECLARE_NARGS("lbu", "<address>",
	    "load unsigned byte from address", 1, run_load),
	SC_DECLARE_NARGS("lhu", "<address>",
	    "load unsigned half word from address", 1, run_load),
	SC_DECLARE_NARGS("lwu", "<address>",
	    "load unsigned word from address", 1, run_load),
	SC_DECLARE_NARGS("ld", "<address>",
	    "load double word from address", 1, run_load),
	SC_DECLARE_NARGS("sb", "<value> <address>",
	    "store byte value at address", 2, run_store),
	SC_DECLARE_NARGS("sh", "<value> <address>",
	    "store half word value at address", 2, run_store),
	SC_DECLARE_NARGS("sw", "<value> <address>",
	    "store word value at address", 2, run_store),
	SC_DECLARE_NARGS("sd", "<value> <address>",
	    "store doubl word value at address", 2, run_store),

	SC_DECLARE_HEADER("Tracing"),
	{
		"memtrace", "<n-events>",
		"trace the execution of some number of instructions",
		NULL, 1, 1, generic_usage, run_trace,
		SC_FLAG_HIDDEN
	},
	/* XXX should take a file name */
	SC_DECLARE_ZEROARGS("settracefilter",
	    "set a trace filter from stream_trace_filter.config",
	    run_zeroargs),
	{
		"streamtrace", "[-b] [<trace-batches>]",
		"receive a stream of trace data (~4070 per batch)",
		"bw", 0, 1, generic_usage, run_trace, 0
	},
	SC_DECLARE_NARGS("printtrace", "<trace-file>",
	    "print a binary trace file in human readable form", 1,
	    run_trace),

	SC_DECLARE_HEADER("Device debugging"),
	SC_DECLARE_NARGS("dumpatse", "<address>",
	    "dump all atse(4) MAC control registers", 1, run_dumpdevice),
	/* XXX: Altera specific? */
	SC_DECLARE_NARGS("dumpfifo", "<address>",
	    "dump status and metadata of a fifo", 1, run_dumpdevice),
	/* XXX: should take an address */
	SC_DECLARE_ZEROARGS("dumppic", "dump PIC status", run_zeroargs),

	SC_DECLARE_HEADER("Help"),
	{
		"help", "<command>",
		"display help for command",
		NULL, 0, 1, help_usage, help_command, 0
	},
	SC_DECLARE_ZEROARGS("man", "display the berictl manpage", run_man),

	SC_DECLARE_END
};

static char *berictl_path;

static struct beri_debug *bdp;
static const char *cablep, *socketp;
static int bflag, uflag, wflag, zflag;

static void
generic_usage(struct subcommand *scp) {
	
	assert(scp->sc_name != NULL);
	assert(scp->sc_desc != NULL);

	printf("%s: %s\n", scp->sc_name, scp->sc_desc);
	printf("usage: %s%s%s\n", scp->sc_name,
	    scp->sc_argsummary != NULL ? " " : "",
	    scp->sc_argsummary != NULL ? scp->sc_argsummary : "");
}

static int
run_boot(struct subcommand *scp, int argc, char **argv)
{

	assert(strcmp("boot", scp->sc_name) == 0);

	/* XXX: will take an argument once we rework the boot process */
	return (berictl_setreg(bdp, "13", "0"));
}

static int
run_console(struct subcommand *scp, int argc, char **argv)
{

	assert(strcmp("console", scp->sc_name) == 0);
	
	return (berictl_console(bdp, socketp, cablep));
}

static int
run_dumpdevice(struct subcommand *scp, int argc, char **argv)
{

	/* XXX: validate argv[0] as an address */

	if (strcmp("dumpatse", scp->sc_name) == 0)
		return (berictl_dumpatse(bdp, argv[0]));
	else if (strcmp("dumpfifo", scp->sc_name) == 0)
		return (berictl_dumpfifo(bdp, argv[0]));
	else
		errx(EXIT_FAILURE,
		    "PROGRAMMER ERROR: %s called with unhandled command %s",
		    __func__, scp->sc_name);
}

static int
run_load(struct subcommand *scp, int argc, char **argv)
{

	/* XXX: validate argv[0] as an address */

	if (strcmp("lbu", scp->sc_name) == 0)
		return (berictl_lbu(bdp, argv[0]));
	else if (strcmp("lhu", scp->sc_name) == 0)
		return (berictl_lhu(bdp, argv[0]));
	else if (strcmp("lwu", scp->sc_name) == 0)
		return (berictl_lwu(bdp, argv[0]));
	else if (strcmp("ld", scp->sc_name) == 0)
		return (berictl_ld(bdp, argv[0]));
	else
		errx(EXIT_FAILURE,
		    "PROGRAMMER ERROR: %s called with unhandled command %s",
		    __func__, scp->sc_name);
}

static int
run_loadfile(struct subcommand *scp, int argc, char **argv)
{
	int len, ret;
	const char *extension = "";
	char *extracted_name;
	char *fullname;

	if ((fullname = realpath(argv[0], NULL)) == NULL) {
		warn("%s: realpath", scp->sc_name);
		return (BERI_DEBUG_USAGE_ERROR);
	}

	if (strcmp("loadsof", scp->sc_name) == 0) {
		if (!zflag && ((len = strlen(fullname)) < 5 ||
		    strcmp(".sof", fullname + (len - 4)) != 0)) {
			warnx("loadsof: file must end in .sof");
			return (BERI_DEBUG_USAGE_ERROR);
		} else
			extension = ".sof";
	}

	if (zflag) {
		if ((extracted_name = extract_file(fullname, extension))
		    == NULL) {
			free(fullname);
			warnx("%s: failed to extract %s", scp->sc_name,
			    argv[0]);
			return (BERI_DEBUG_USAGE_ERROR);
		}
		free(fullname);
		fullname = extracted_name;
	}

	if (strcmp("loadsof", scp->sc_name) == 0) {
		assert (argc == 1);
		return(berictl_loadsof(fullname, cablep));
	}

	/* XXX: validate argv[1] as an address */
	assert(argc == 2);
	if (strcmp("loadbin", scp->sc_name) == 0)
		ret = berictl_loadbin(bdp, argv[1], fullname);
	else if (strcmp("loaddram", scp->sc_name) == 0)
		ret = berictl_loaddram(bdp, argv[1], fullname, cablep);
	else
		errx(EXIT_FAILURE,
		    "PROGRAMMER ERROR: %s called with unhandled command %s",
		    __func__, scp->sc_name);

	free(fullname);
	return (ret);
}

static int
run_man(struct subcommand *scp, int argc, char **argv)
{
	char *berictl_rpath, *manpage, *prog;

	if (berictl_path != NULL &&
	    (berictl_rpath = which(berictl_path)) != NULL) {
		if (asprintf(&manpage, "%s.1", berictl_rpath) > 0) {
			if ((prog = which("mandoc")) != NULL) {
				execl(prog, prog, manpage, NULL);
				exit(1);
			} else if ((prog = which("nroff")) != NULL) {
				execl(prog, prog, "-S", "-Tascii", "-man",
				    manpage, NULL);
				exit(1);
			}
		}
		free(berictl_rpath);
		free(manpage);
	}
	execlp("man", "man", "1", "berictl", NULL);
	exit(1);
}

static int
run_setaddr(struct subcommand *scp, int argc, char **argv)
{

	if (strcmp("setreg", scp->sc_name) == 0) {
		/* XXX validate argv[0] as reg number and argv[1] as addr */
		assert(argc == 2);
		return (berictl_setreg(bdp, argv[0], argv[1]));
	}
	
	assert(argc == 1);
	if (strcmp("breakpoint", scp->sc_name) == 0)
		return (berictl_breakpoint(bdp, argv[0], wflag));
	else if (strcmp("setpc", scp->sc_name) == 0)
		return (berictl_setpc(bdp, argv[0]));
	else if (strcmp("setthread", scp->sc_name) == 0)
		return (berictl_setthread(bdp, argv[0]));
	else
		errx(EXIT_FAILURE,
		    "PROGRAMMER ERROR: %s called with unhandled command %s",
		    __func__, scp->sc_name);
}

static int
run_store(struct subcommand *scp, int argc, char **argv)
{

	assert(argc == 2);
	
	/* XXX: validate argv[0] as a value and argv[1] as an address */
	if (strcmp("sb", scp->sc_name) == 0)
		return (berictl_sb(bdp, argv[1], argv[0]));
	else if (strcmp("sh", scp->sc_name) == 0)
		return (berictl_sh(bdp, argv[1], argv[0]));
	else if (strcmp("sw", scp->sc_name) == 0)
		return (berictl_sw(bdp, argv[1], argv[0]));
	else if (strcmp("sd", scp->sc_name) == 0)
		return (berictl_sd(bdp, argv[1], argv[0]));
	else
		errx(EXIT_FAILURE,
		    "PROGRAMMER ERROR: %s called with unhandled command %s",
		    __func__, scp->sc_name);
}

static int
run_trace(struct subcommand *scp, int argc, char **argv)
{
	int batches;
	char *endp;
	
	if (strcmp("memtrace", scp->sc_name) == 0) {
		assert(argc == 1);
		return (berictl_mem_trace(bdp, argv[0]));
	} else if (strcmp("streamtrace", scp->sc_name) == 0) {
		if (argc == 1) {
			if (wflag) {
				warnx("-w and trace-batches are incompatible");
				return (BERI_DEBUG_USAGE_ERROR);
			}
			if (*argv[0] == '\0') {
				warnx("invalid trace-batches '%s'\n", argv[0]);
				return (BERI_DEBUG_USAGE_ERROR);
			}
			batches = strtol(argv[0], &endp, 10);
			if (batches < 0 || *endp != '\0') {
				warnx("invalid trace-batches '%s'\n", argv[0]);
				return (BERI_DEBUG_USAGE_ERROR);
			}
		} else {
			assert(argc == 0);
			batches = 4;
			if (wflag) {
				warnx("-w is deprecated");
				batches = 256;
			}
		}
		return (berictl_stream_trace(bdp, batches, bflag));
	} else if (strcmp("printtrace", scp->sc_name) == 0) {
		assert(argc == 1);
		return(berictl_print_traces(bdp, argv[0]));
	} else
		errx(EXIT_FAILURE,
		    "PROGRAMMER ERROR: %s called with unhandled command %s",
		    __func__, scp->sc_name);
}

static int
run_zeroargs(struct subcommand *scp, int argc, char **argv)
{

	assert(argc == 0);

	if (strcmp("c0regs", scp->sc_name) == 0)
		return (berictl_c0regs(bdp));
	else if (strcmp("c2regs", scp->sc_name) == 0)
		return (berictl_c2regs(bdp));
	else if (strcmp("cleanup", scp->sc_name) == 0)
		return (beri_debug_cleanup());
	else if (strcmp("drain", scp->sc_name) == 0)
		return (berictl_drain(bdp));
	else if (strcmp("dumppic", scp->sc_name) == 0)
		return (berictl_dumppic(bdp));
	else if (strcmp("pause", scp->sc_name) == 0)
		return (berictl_pause(bdp));
	else if (strcmp("pc", scp->sc_name) == 0)
		return (berictl_pc(bdp));
	else if (strcmp("regs", scp->sc_name) == 0)
		return (berictl_regs(bdp));
	else if (strcmp("reset", scp->sc_name) == 0)
		return (berictl_reset(bdp));
	else if (strcmp("resume", scp->sc_name) == 0)
		if (uflag)
			return (berictl_unpipeline(bdp));
		else
			return (berictl_resume(bdp));
	else if (strcmp("settracefilter", scp->sc_name) == 0)
		return (berictl_set_trace_filter(bdp));
	else if (strcmp("step", scp->sc_name) == 0)
		return (berictl_step(bdp));
	else
		errx(EXIT_FAILURE,
		    "PROGRAMMER ERROR: %s called with unhandled command %s",
		    __func__, scp->sc_name);
}

static void
close_bdp(void)
{

	if (bdp != NULL)
		beri_debug_client_close(bdp);
}

static void
usage(void)
{
	struct subcommand *scp;

	printf("usage: berictl ");
#ifdef BERI_NETFPGA
	printf("[-2dNnq] ");
#else
	printf("[-2dNq] ");
#endif
	printf("[-c <cable>] [-s <socket-path-or-port>] <command> [<args>]\n");
	for (scp = berictl_commands; !SC_IS_END(scp); scp++) {
		if (SC_IS_HIDDEN(scp))
			continue;
		if (SC_IS_HEADER(scp))
			printf("\n%s\n", scp->sc_desc);
		else
			printf("   %-16s%s\n", scp->sc_name, scp->sc_desc);
	}
}

static int
help_command(struct subcommand *scp, int argc, char **argv)
{
	struct subcommand *tmpscp;

	if (argc == 0) {
		usage();
		return (BERI_DEBUG_SUCCESS);
	}
	if (argc > 1)
		return (BERI_DEBUG_USAGE_ERROR);

	if (strcmp("arg-summary", argv[0]) == 0) {
		printf("Summary of commands and  arguments:\n");
		for (tmpscp = berictl_commands; !SC_IS_END(tmpscp); tmpscp++) {
			if (!SC_IS_HEADER(tmpscp))
				printf("   %s%s%s\n", tmpscp->sc_name,
				    tmpscp->sc_argsummary != NULL ? " " : "",
				    tmpscp->sc_argsummary != NULL ?
				    tmpscp->sc_argsummary : "");
		}
		return (BERI_DEBUG_SUCCESS);
	}

	for (tmpscp = berictl_commands; !SC_IS_END(tmpscp); tmpscp++)
		if (SC_IS_COMMAND(tmpscp) &&
		    strcmp(argv[0], tmpscp->sc_name) == 0)
			break;
	if (SC_IS_END(tmpscp)) {
		warnx("unknown command %s", argv[0]);
		return (BERI_DEBUG_USAGE_ERROR);
	}
	tmpscp->sc_usage(tmpscp);
	return (BERI_DEBUG_SUCCESS);
}

static void
help_usage(struct subcommand *scp)
{

	generic_usage(scp);

	printf("\n");
	printf("Pseudo-commands:\n");
	printf("   arg-summary      print a summary of commands and arguments\n");
}

static void
loadfile_usage(struct subcommand *scp)
{

	generic_usage(scp);

	printf("  -z\t: Extract the (bzip2 compressed) file before loading\n");
}

static void
loadsof_usage(struct subcommand *scp)
{
	
	loadfile_usage(scp);

	printf("\n");
	printf("Note: if the file is not compressed it must end in. sof\n");
}

int
main(int argc, char *argv[])
{
	int opt, ret;
	uint32_t oflags;
	struct subcommand *scp;

	bdp = NULL;

	cablep = NULL;
	socketp = NULL;

	berictl_path = argv[0];

	oflags = BERI_DEBUG_CLIENT_OPEN_FLAGS_SOCKET;

	while ((opt = getopt(argc, argv, _GETOPT_PLUS"2c:dNns:q")) != -1) {
		switch (opt) {
		case '2':
			oflags |= BERI_DEBUG_CLIENT_OPEN_FLAGS_BERI2;
			break;

		case 'c':
			cablep = optarg;
			break;

		case 'd':
			debugflag++;
			break;

		case 'N':
			oflags |= BERI_DEBUG_CLIENT_OPEN_FLAGS_NO_PAUSE_RESUME;
			break;

		case 'n':
#ifdef BERI_NETFPGA
			oflags |= BERI_DEBUG_CLIENT_OPEN_FLAGS_NETFPGA;
#else
			usage();
			exit(EXIT_FAILURE);
#endif
			break;

		case 'q':
			quietflag++;
			break;

		case 's':
			socketp = optarg;
			break;
		default:
			warnx("Invalid argument before command");
			usage();
			exit(EXIT_FAILURE);
		}
	}
	argc-=optind;
	argv+=optind;

	if (argc < 1) {
		warnx("no command given");
		usage();
		exit(EXIT_FAILURE);
	}

	for (scp = berictl_commands; !SC_IS_END(scp); scp++)
		if (SC_IS_COMMAND(scp) && strcmp(argv[0],
		    scp->sc_name) == 0)
			break;
	if (SC_IS_END(scp)) {
		warnx("unknown command %s", argv[0]);
		usage();
		exit(EXIT_FAILURE);
	}
	if (debugflag > 0)
		printf("command = %s\n", scp->sc_name);

	/* Restart getopt() processing from scratch for new command line. */
	optind = 1;

	bflag = 0;
	uflag = 0;
	wflag = 0;
	zflag = 0;
	if (scp->sc_getoptstr != NULL) {
		if (debugflag > 1 && argc > 0)
			printf("getopt(%d, {%s, ...}, %s)\n",
			    argc, argv[0], scp->sc_getoptstr);
		opterr = 0;
#ifdef __FreeBSD__
		optreset = 1;
#endif
		while ((opt = getopt(argc, argv, scp->sc_getoptstr)) != -1) {
			switch (opt) {
			case 'b':
				bflag++;
				break;

			case 'u':
				uflag++;
				break;

			case 'w':
				wflag++;
				break;

			case 'z':
				zflag++;
				break;

			case '?':
				warnx("%s: illegal option -- %c",
				    scp->sc_name, optopt);
				if (scp->sc_usage != NULL)
					scp->sc_usage(scp);
				exit(EXIT_FAILURE);

			default:
				errx(EXIT_FAILURE, "PROGRAMMER ERROR: "
				    "%s requested -%c and it is unhandled",
				    scp->sc_name, opt);
			}
		}
	}
	argc -= optind;
	argv += optind;

	if (argc < scp->sc_minargs) {
		warnx("%s: too few arguments", scp->sc_name);
		if (scp->sc_usage != NULL)
			scp->sc_usage(scp);
		exit(EXIT_FAILURE);
	}
	if (argc > scp->sc_maxargs) {
		warnx("%s: too many arguments", scp->sc_name);
		if (scp->sc_usage != NULL)
			scp->sc_usage(scp);
		exit(EXIT_FAILURE);
	}

	/* XXX: should be a flag in struct subcommand. */
	if (strcmp("cleanup", scp->sc_name) != 0 &&
	    (strcmp("console", scp->sc_name) != 0 ||
		((strcmp("console", scp->sc_name) == 0) &&
		(oflags & BERI_DEBUG_CLIENT_OPEN_FLAGS_NETFPGA) != 0)) &&
	    strcmp("help", scp->sc_name) != 0 &&
	    strcmp("loadsof", scp->sc_name) != 0 &&
	    strcmp("man", scp->sc_name) != 0 &&
	    strcmp("printtrace", scp->sc_name) != 0) {
		if (socketp != NULL)
			ret = beri_debug_client_open_path(&bdp, socketp,
			    oflags);
		else
			ret = beri_debug_client_open(&bdp, oflags);
		if (ret != BERI_DEBUG_SUCCESS) {
			if (strcmp("loaddram", scp->sc_name) == 0)
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
	}
	ret = scp->sc_command(scp, argc, argv);

	if (ret == BERI_DEBUG_USAGE_ERROR)
		scp->sc_usage(scp);

	if (ret != BERI_DEBUG_SUCCESS && ret != BERI_DEBUG_USAGE_ERROR)
		err(EXIT_FAILURE, "%s: %s", scp->sc_name,
		     beri_debug_strerror(ret));
	exit(EXIT_SUCCESS);
}
