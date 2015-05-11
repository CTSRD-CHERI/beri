/*-
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2011-2013 Jonathan Woodruff
 * Copyright (c) 2012-2013 SRI International
 * Copyright (c) 2012 Robert Norton
 * Copyright (c) 2013 Bjoern A. Zeeb
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2015 A. Theodore Markettos
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

#ifndef BERI_DEBUG_H
#define	BERI_DEBUG_H

/*
 * Parameters for the local domain sockets used to control the BERI debug
 * units.
 */
#define	BERI_DEBUG_SOCKET_COUNT			2
#define	BERI_DEBUG_SOCKET_PATH_ENV_0		"BERI_DEBUG_SOCKET_0"
#define	BERI_DEBUG_SOCKET_PATH_DEFAULT_0	"/tmp/beri_debug_listen_socket_0"
#define	BERI_DEBUG_SOCKET_PATH_ENV_1		"BERI_DEBUG_SOCKET_1"
#define	BERI_DEBUG_SOCKET_PATH_DEFAULT_1	"/tmp/beri_debug_listen_socket_1"
#define	BERI_DEBUG_SOCKET_TRACING_ENV		"BERI_DEBUG_SOCKET_TRACING"

/*
 * Return values from BERI debug library functions.
 */
#define	BERI_DEBUG_USAGE_ERROR			(-1)	/* Error due to construction */
#define	BERI_DEBUG_SUCCESS			0	/* Success.*/
#define	BERI_DEBUG_ERROR_SOCKET		1	/* In socket(). */
#define	BERI_DEBUG_ERROR_CONNECT		2	/* In connect(). */
#define	BERI_DEBUG_ERROR_SEND			3	/* In send(). */
#define	BERI_DEBUG_ERROR_BPBOUND		4	/* Out-of-bounds BP. */
#define	BERI_DEBUG_ERROR_REGBOUND		5	/* Out-of-bounds reg. */
#define	BERI_DEBUG_ERROR_IMMBOUND		6	/* Out-of-bounds imm. */
#define	BERI_DEBUG_ERROR_DATA_UNEXPECTED	7	/* Unexpected data. */
#define	BERI_DEBUG_ERROR_DATA_TOOBIG		8	/* Too much sent. */
#define	BERI_DEBUG_ERROR_ADDR_INVALID		9	/* Invalid address. */
#define	BERI_DEBUG_ERROR_UNSUPPORTED		10	/* Unsupported req. */
#define	BERI_DEBUG_ERROR_EXCEPTION		11	/* Exception fired. */
#define	BERI_DEBUG_ERROR_NOBREAK		12	/* BP hasn't fired. */
#define	BERI_DEBUG_ERROR_OPEN			13	/* Nn open(). */
#define	BERI_DEBUG_ERROR_STAT			14	/* In fstat()/stat(). */
#define	BERI_DEBUG_ERROR_READ			15	/* In read(). */
#define	BERI_DEBUG_ERROR_SOCKETPAIR		16	/* In socketpair(). */
#define	BERI_DEBUG_ERROR_FORK			17	/* In fork(). */
#define	BERI_DEBUG_ERROR_MALLOC		18	/* Memory allocation. */
#define BERI_DEBUG_ERROR_INVALID_TRACECOUNT	19	/* Trace number count. */
#define	BERI_DEBUG_ERROR_NOTPAUSED		20
#define	BERI_DEBUG_ERROR_WRONGRESPONSE		21
#define	BERI_DEBUG_ERROR_INCOMPLETE		22	/* Need more data. */
#define	BERI_DEBUG_ERROR_ALTERA_SOFTWARE	23	/* Altera error. */
#define	BERI_DEBUG_ERROR_PCIEXPRESS_DISABLED	24	/* Built without PCI Express. */
#define	BERI_DEBUG_ERROR_ATLANTIC_OPEN		25	/* Couldn't open JTAG Atlantic connection */

/*
 * BERI debug instructions, sorted alphabetically by character.
 */
#define	BERI_DEBUG_OP_LOAD_BREAKPOINT_0	'0'	/* 64-bit arg */
#define	BERI_DEBUG_OP_LOAD_BREAKPOINT_1	'1'	/* 64-bit arg */
#define	BERI_DEBUG_OP_LOAD_BREAKPOINT_2	'2'	/* 64-bit arg */
#define	BERI_DEBUG_OP_LOAD_BREAKPOINT_3	'3'	/* 64-bit arg */
#define	BERI_DEBUG_OP_LOAD_OPERAND_A		'a'	/* 64-bit arg */
#define	BERI_DEBUG_OP_LOAD_OPERAND_B		'b'	/* 64-bit arg */
#define	BERI_DEBUG_OP_BREAK_ON_TRACE_FILTER	'B'
#define	BERI_DEBUG_OP_LOAD_TRACE_FILTER	'C'	/* 256-bit arg */
#define	BERI_DEBUG_OP_LOAD_TRACE_FILTER_MASK	'M'	/* 256-bit arg */
#define	BERI_DEBUG_OP_MOVE_PC_TO_DESTINATION	'c'
#define	BERI_DEBUG_OP_REPORT_DESTINATION	'd'	/* 64-bit ret */
#define	BERI_DEBUG_OP_EXECUTE_INSTRUCTION	'e'
#define	BERI_DEBUG_OP_LOAD_INSTRUCTION		'i'	/* 32-bit arg */
#define	BERI_DEBUG_OP_PAUSE_EXECUTION		'p'
#define	BERI_DEBUG_OP_RESUME_EXECUTION		'r'
#define	BERI_DEBUG_OP_RESET			'R'
#define	BERI_DEBUG_OP_STEP_EXECUTION		's'
#define	BERI_DEBUG_OP_STREAM_TRACE_START	'S'
#define	BERI_DEBUG_OP_POP_TRACE		't'
#define	BERI_DEBUG_OP_UNPIPELINE_EXECUTION	'u'
#define	BERI_DEBUG_OP_MEM_TRACE		'T'
/*
 * Alternative error responses that may come back instead of the same opcode
 * with BERI_DEBUG_REPLY() set.  These must be explicitly checked for and
 * do not require use of BERI_DEBUG_REPLY().
 */
#define	BERI_DEBUG_ER_INVALID			' '	/* Invalid op reply. */
#define	BERI_DEBUG_ER_EXCEPTION		0xc5	/* Exception fired. */

/*
 * BERI2 debug instructions
 */
#define	BERI2_DEBUG_OP_PAUSEPIPELINE		0
#define	BERI2_DEBUG_OP_RESUMEPIPELINE		2
#define	BERI2_DEBUG_OP_RESUMEUNPIPELINED	4
#define	BERI2_DEBUG_OP_SETPC			6
#define	BERI2_DEBUG_OP_GETPC			8
#define	BERI2_DEBUG_OP_SETBYTE			10
#define	BERI2_DEBUG_OP_GETBYTE			12
#define	BERI2_DEBUG_OP_SETHALFWORD		14
#define	BERI2_DEBUG_OP_GETHALFWORD		16
#define	BERI2_DEBUG_OP_SETWORD			18
#define	BERI2_DEBUG_OP_GETWORD			20
#define	BERI2_DEBUG_OP_SETDOUBLEWORD		22
#define	BERI2_DEBUG_OP_GETDOUBLEWORD		24
#define	BERI2_DEBUG_OP_SETREGISTER		26
#define	BERI2_DEBUG_OP_GETREGISTER		28
#define	BERI2_DEBUG_OP_SETC0REGISTER		30
#define	BERI2_DEBUG_OP_GETC0REGISTER		32
#define	BERI2_DEBUG_OP_SETC2REGISTER		34
#define	BERI2_DEBUG_OP_GETC2REGISTER		36
#define	BERI2_DEBUG_OP_EXECUTESINGLEINST	38
#define	BERI2_DEBUG_OP_SETBREAKPOINT		40
#define	BERI2_DEBUG_OP_POPTRACE		42
#define	BERI2_DEBUG_OP_SETTRACEMASK		44
#define	BERI2_DEBUG_OP_SETTRACEFILTER		48
#define	BERI2_DEBUG_OP_RESUMESTREAMING		50
#define	BERI2_DEBUG_OP_SETTHREAD		52

/*
 * Asynchronous events -- the same namespace as debug instructions.  These do
 * not require using BERI_DEBUG_REPLY().
 */
#define	BERI_DEBUG_EV_BREAKPOINT_FIRED		0xff
#define	BERI2_DEBUG_EV_BREAKPOINT_FIRED	0x2E
#define	BERI2_DEBUG_EV_EXCEPTION		0x2F

/*
 * Replies contain the request op with its top bit set.
 */
#define	BERI_DEBUG_REPLY(command)	((command) | (1 << 7))

/*
 * BERI2 replies contain the op request with the LSB set.
 */
#define	BERI2_DEBUG_REPLY(command)	((command) + 1)

/*
 * BERI2 Pipeline states
 */
#define	BERI2_DEBUG_STATE_UNKNOWN        (-1)
#define	BERI2_DEBUG_STATE_PAUSED         0
#define	BERI2_DEBUG_STATE_RUNPIPELINED   1
#define	BERI2_DEBUG_STATE_RUNUNPIPELINED 2
#define	BERI2_DEBUG_STATE_RUNSTREAMING   3

/*
 * Useful MIPS64 and BERI debug unit constants for debuggers.
 */
#define	BERI_DEBUG_REGNUM_DESTINATION		0
#define	BERI_DEBUG_REGNUM_DONTCARE		BERI_DEBUG_REGNUM_DESTINATION

/*
 * Magic breakpoint value.
 */
#define	BERI_DEBUG_BREAKPOINT_DISABLED		(0xffffffffffffffff)

/*
 * Capability Register Fields
 */
#define	CHERI_DEBUG_CAP_PERMISSIONS	0x0
#define	CHERI_DEBUG_CAP_TYPE		0x1
#define	CHERI_DEBUG_CAP_BASE		0x2
#define	CHERI_DEBUG_CAP_LENGTH		0x3
#define	CHERI_DEBUG_CAP_TAG		0x5
#define	CHERI_DEBUG_CAP_UNSEALED	0x6

/*
 * Capability Link Register
 */
#define	CHERI_DEBUG_CAPABILITY_LINK_REG	26

/*
 * Client-side APIs for constructing useful big-endian MIPS64 instructions to
 * feed into the CHERI debug unit.
 */
int	mips64be_make_ins_daddu(u_int, u_int, u_int, uint32_t *);
int	mips64be_make_ins_jr(u_int, uint32_t *);
int	mips64be_make_ins_move(u_int, u_int, uint32_t *);
int	mips64be_make_ins_lbu(u_int, u_int, u_int, uint32_t *);
int	mips64be_make_ins_ld(u_int, u_int, u_int, uint32_t *);
int	mips64be_make_ins_dmfc0(u_int, u_int, u_int, uint32_t *);
int	mips64be_make_ins_dmfc2(u_int, u_int, u_int, uint32_t *);
int	mips64be_make_ins_nop(uint32_t *);
int	mips64be_make_ins_sb(u_int, u_int, u_int, uint32_t *);
int	mips64be_make_ins_sd(u_int, u_int, u_int, uint32_t *);
int	mips64be_make_ins_cache_invalidate(u_int, u_int, uint32_t *);

struct beri_debug_trace_entry {
	uint64_t	val1;
	uint64_t	val2;
	uint64_t	pc;
	uint32_t	inst;
	uint16_t	reserved  : 3;
	uint16_t	branch    : 1;
	uint16_t	asid      : 8;
	uint16_t	cycles    : 10;
	uint16_t	exception : 5;
	uint16_t	version   : 4;
	uint16_t	valid     : 1;
} __attribute__((packed)); 

/**
 * BERI debug record in on-disk format.  The values are all stored in
 * big-endian representation.
 */
struct beri_debug_trace_entry_disk {
	uint8_t		version;
	uint8_t		exception;
	uint16_t	cycles;
	uint32_t	inst;
	uint64_t	pc;
	uint64_t	val1;
	uint64_t	val2;
} __attribute__((packed));

/* Another version of above with support for extra fields -- enabled
   via -2 flag to streamtrace */
struct beri_debug_trace_entry_disk_v2 {
	uint8_t		version;
	uint8_t		exception;
	uint16_t	cycles;
	uint32_t	inst;
	uint64_t	pc;
	uint64_t	val1;
	uint64_t	val2;
	uint8_t		thread;
	uint8_t		asid;
} __attribute__((packed));

struct cap {
	uint64_t	length;
	uint64_t	base;
	uint64_t	type;
  uint64_t	unsealed :1;
  uint64_t	perms    :63;
	uint8_t		tag;
} __attribute__((packed));

/*
 * Client-side APIs for connecting to/disconnecting from the BERI debugging
 * unit.
 */
#define	BERI_DEBUG_CLIENT_OPEN_FLAGS_SOCKET			0x00000000
#define	BERI_DEBUG_CLIENT_OPEN_FLAGS_NETFPGA			0x00000001
#define	BERI_DEBUG_CLIENT_OPEN_FLAGS_BERI2			0x00000002
#define	BERI_DEBUG_CLIENT_OPEN_FLAGS_NO_PAUSE_RESUME		0x00000004
#define	BERI_DEBUG_CLIENT_OPEN_FLAGS_PCIEXPRESS			0x00000008
#define	BERI_DEBUG_CLIENT_OPEN_FLAGS_ARM_SOCKIT			0x00000010
#define	BERI_DEBUG_CLIENT_OPEN_FLAGS_JTAG_ATLANTIC		0x00000020

struct beri_debug;
const char *	beri_debug_strerror(int);
int	beri_debug_cleanup(void);
int	beri_debug_get_outstanding_max(struct beri_debug *);
int	beri_debug_client_open_path(struct beri_debug **, const char *,
	    uint32_t);
int	beri_debug_client_open(struct beri_debug **, uint32_t);
int	beri_debug_client_open_nios(struct beri_debug **, const char *,
	    const char *, int, uint32_t);
int	beri_debug_client_open_pcie(struct beri_debug **, uint32_t);
int	beri_debug_client_open_sockit(struct beri_debug **, uint32_t);
int	beri_debug_client_open_jtag_atlantic(struct beri_debug **, 
		const char *, const char *, int, uint32_t);
int	beri_debug_client_open_sc(struct beri_debug **, uint32_t);
void	beri_debug_client_close(struct beri_debug *);
int	beri_debug_client_drain(struct beri_debug *);
int	beri_debug_client_load_instruction(struct beri_debug *, uint32_t);
int	beri_debug_client_breakpoint_check(struct beri_debug *, uint64_t *);
int	beri_debug_client_breakpoint_clear(struct beri_debug *, u_int);
int	beri_debug_client_breakpoint_set(struct beri_debug *, u_int,
	    uint64_t);
int	beri_debug_client_breakpoint_wait(struct beri_debug *, uint64_t *);
int	beri_debug_client_load_operand_a(struct beri_debug *, uint64_t);
int	beri_debug_client_load_operand_b(struct beri_debug *, uint64_t);
int	beri_debug_client_execute_instruction(struct beri_debug *,
	    uint8_t *excodep);
int	beri_debug_client_move_pc_to_destination(struct beri_debug *);
int	beri_debug_client_report_destination(struct beri_debug *,
	    uint64_t *);
int	beri_debug_client_pause_execution(struct beri_debug *);
int	beri_debug_client_resume_execution(struct beri_debug *);
int	beri_debug_client_step_execution(struct beri_debug *);
int	beri_debug_client_unpipeline_execution(struct beri_debug *);

void	beri2_print_pipeline_state(struct beri_debug *, uint8_t);
int	beri_debug_client_get_pipeline_state(struct beri_debug *);
int	beri_debug_client_set_pipeline_state(struct beri_debug *, uint8_t,
	    uint8_t *);
int	beri_debug_client_pause_pipeline(struct beri_debug *, uint8_t *);

/*
 * Client-side APIs for meta-operations such as querying general-purpose and
 * coprocessor register values.
 */

int	beri_debug_client_get_reg(struct beri_debug *, u_int, uint64_t *);
int 	beri_debug_client_get_reg_pipelined_send(struct beri_debug *,
	    u_int);
int 	beri_debug_client_get_reg_pipelined_response(struct beri_debug *,
	    uint64_t *);
int	beri_debug_client_get_pc(struct beri_debug *, uint64_t *);
int	beri_debug_client_get_c0reg(struct beri_debug *, u_int, uint64_t *);
int 	beri_debug_client_get_c0reg_pipelined_send(struct beri_debug *,
	    u_int, u_int);
int 	cheri_debug_client_get_c2reg(struct beri_debug *, uint8_t, struct cap *);
int 	cheri_debug_client_pcc_to_cr26(struct beri_debug *);
int 	cheri_debug_client_get_c2reg_pipelined_send(struct beri_debug *, u_int,
	    u_int);
int 	mips64be_make_ins_cjr(u_int, u_int, uint32_t *);
int 	mips64be_make_ins_cjalr(u_int, u_int, uint32_t *);
int	beri_debug_client_lbu(struct beri_debug *, uint64_t, uint8_t *,
	    uint8_t *);
int	beri_debug_client_lhu(struct beri_debug *, uint64_t, uint16_t *,
	    uint8_t *);
int	beri_debug_client_lwu(struct beri_debug *, uint64_t, uint32_t *,
	    uint8_t *);
int	beri_debug_client_ld(struct beri_debug *, uint64_t, uint64_t *,
	    uint8_t *);
int	beri_debug_client_sb(struct beri_debug *, uint64_t, uint8_t,
	    uint8_t *);
int	beri_debug_client_sh(struct beri_debug *, uint64_t, uint16_t,
	    uint8_t *);
int	beri_debug_client_sw(struct beri_debug *, uint64_t, uint32_t,
	    uint8_t *);
int	beri_debug_client_sd(struct beri_debug *, uint64_t, uint64_t,
	    uint8_t *);
int	beri_debug_client_sd_pipelined_send(struct beri_debug *, uint64_t,
	    uint64_t);
int	beri_debug_client_sd_pipelined_response(struct beri_debug *,
	    uint8_t *);
int	beri_debug_client_sh_pipelined_send(struct beri_debug *, uint64_t,
	    uint16_t);
int	beri_debug_client_sh_pipelined_response(struct beri_debug *,
	    uint8_t *);
int	beri_debug_client_nop_pipelined_send(struct beri_debug *);
int	beri_debug_client_nop_pipelined_response(struct beri_debug *,
	    uint8_t *);
int 	beri_debug_client_invalidateicache(struct beri_debug *);
int	beri_debug_client_reset(struct beri_debug *);
int	beri_debug_client_set_pc(struct beri_debug *, uint64_t);
int	beri_debug_client_set_thread(struct beri_debug *, uint8_t);
int	beri_debug_client_set_reg(struct beri_debug *, u_int, uint64_t);
int	beri_debug_client_stream_trace_start(struct beri_debug *);
int     beri_debug_client_pop_trace_send(struct beri_debug *);
int     beri_debug_client_pop_trace_receive(struct beri_debug *,
                struct beri_debug_trace_entry *);
int	beri_trace_filter_set(struct beri_debug *,
                struct beri_debug_trace_entry *);
int	beri_trace_filter_mask_set(struct beri_debug *,
                struct beri_debug_trace_entry *);
int     beri_break_on_trace_filter(struct beri_debug *bdp);
void    intHandler(int);

static const char* const exception_codes[] = 
  {
"Interrupt",// 0
"TLBModified",// 1
"TLBLoadMiss",// 2
"TLBStoreMiss",// 3
"AddrErrLoad",// 4 
"AddrErrStore",// 5 
"InstBusErr",// 6 // implementation dependent
"DataBusErr",// 7 // implementation dependent
"SysCall",// 8
"BreakPoint",// 9 
"ReservedInst",// 10 // reserved instruction exception (opcode not recognized) XXX could use better name
"CoProcess1",// 11 Attempted coprocessor inst for disabled coprocessor. Floating point emulation starts here.
"Overflow",// 12 Overflow from trapping arithmetic instructions (e.g. add, but not addu).
"Trap",// 13
"CP2Trap(cheri2)",// 14 CP2 Trap (CCall, CReturn) INTERNAL
"FloatingPoint",// 15
"TLBLoadCap",// 16 TLB cap load forbidden CHERI EXTENSION
"TLBStoreCap",// 17 TLB cap store forbidden CHERI EXTENSION
"CoProcess2",// 18 Exception from Coprocessor 2 (extenstion to ISA)
"TLBLoadInst(cheri2)",// 19 TLB instruction miss INTERNAL
"AddrErrInst(cheri2)",// 20 Instruction address error INTERNAL
"TLBInvInst(cheri2)",// 21 TLB instruction load invalid INTERNAL
"MDMX",// 22 Tried to run an MDMX instruction but SR(dspOrMdmx) is not enabled.
"Watch",// 23 Physical address of load and store matched WatchLo/WatchHi registers
"MCheck",// 24 Disasterous error in control system, eg, duplicate entries in TLB.
"Thread",// 25 Thread related exception (check VPEControl(EXCPT))
"DSP",// 26 Unable to do DSP ASE Instruction (lack of DSP)
"Exp27",// 27 Place holder
"TLBLoadInv(cheri2)",// 28 TLB matched but valid bit not set INTERNAL
"TLBStoreInv(cheri2)",// 29 TLB matched but valid bit not set INTERNAL
"CacheErr",// 30 Parity/ECC error in cache.
"None"// 31 No Error
};

/*
 * Internal packet function.
 *
 * XXXRW: Improperly used by berictl_mem_trace.
 */
int	beri_debug_client_packet_write(struct beri_debug *, uint8_t, void *,
	    size_t);

/*
 * Host to BERI endian swap.
 */
uint64_t btoh64(struct beri_debug *cdp, uint64_t v);

/*
 * BERI to host endian swap.
 */
uint64_t htob64(struct beri_debug *cdp, uint64_t v);

/*
 * Map a physical address into virtual address space.
 */
uint64_t physical2virtual(struct beri_debug *bdp, uint64_t v);

#endif /* !BERI_DEBUG_H */
