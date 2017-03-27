/*-
 * Copyright (c) 2011-2013 Robert N. M. Watson
 * Copyright (c) 2012 Jonathan Woodruff
 * Copyright (c) 2012-2013 Bjoern A. Zeeb
 * Copyright (c) 2012-2014 SRI International
 * Copyright (c) 2013 David T. Chisnall
 * Copyright (c) 2013 Colin Rothwell
 * Copyright (c) 2015 Theo Markettos
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
 * Simple CHERI debug tool: various debugging operations can be exercised from
 * the command line, including inspecting register state, pausing, resuming,
 * and single-stepping the processor.
 */

#ifndef _CHERICTL_H_
#define	_CHERICTL_H_

extern int debugflag;
extern int quietflag;

struct sume_ifreq;

int	hex2addr(const char *string, uint64_t *addrp);
int	str2regnum(const char *string, u_int *regnump);

int	berictl_breakpoint(struct beri_debug *bdp, const char *addrp,
	    int waitflag);
int	beri_debug_client_netfpga_sume_ioctl(struct beri_debug *,
	    struct sume_ifreq *, unsigned long, char *);
int	beri_debug_getfd(struct beri_debug *);
int	beri_debug_is_netfpga(struct beri_debug *);
int	beri_debug_is_netfpga_sume(struct beri_debug *);
int	berictl_console(struct beri_debug *, const char *filenamep,
	    const char *cablep, const char *devicep);
int	berictl_c0regs(struct beri_debug *bdp);
int	berictl_c2regs(struct beri_debug *bdp);
int	berictl_drain(struct beri_debug *bdp);
int	berictl_dumpatse(struct beri_debug *, const char *);
int	berictl_dumpfifo(struct beri_debug *, const char *);
int	berictl_dumppic(struct beri_debug *, int pic_id);
int	berictl_get_service_path(struct beri_debug *, const char *cablep,
	    char *path_buffer, size_t pathlen);
int	berictl_lbu(struct beri_debug *bdp, const char *addrp);
int	berictl_lhu(struct beri_debug *bdp, const char *addrp);
int	berictl_lwu(struct beri_debug *bdp, const char *addrp);
int	berictl_ld(struct beri_debug *bdp, const char *addrp);
int	berictl_loadbin(struct beri_debug *bdp, const char *addrp,
	    const char *filep);
int	berictl_loaddram(struct beri_debug *, const char *,
	    const char *, const char *);
int	berictl_loaddram_sockit(struct beri_debug *, const char *,
	    const char *);
int	berictl_loadsof(const char *filep, const char *, const char *);
int	berictl_pause(struct beri_debug *bdp);
int	berictl_unpipeline(struct beri_debug *bdp);
int	berictl_pc(struct beri_debug *bdp);
int	berictl_regs(struct beri_debug *bdp);
int	berictl_resume(struct beri_debug *bdp);
int	berictl_reset(struct beri_debug *bdp);
int	berictl_sb(struct beri_debug *bdp, const char *addrp,
	    const char *valuep);
int	berictl_sh(struct beri_debug *bdp, const char *addrp,
	    const char *valuep);
int	berictl_sw(struct beri_debug *bdp, const char *addrp,
	    const char *valuep);
int	berictl_sd(struct beri_debug *bdp, const char *addrp,
	    const char *valuep);
int	berictl_setpc(struct beri_debug *bdp, const char *addrp);
int	berictl_setthread(struct beri_debug *bdp, const char *thread);
int	berictl_setreg(struct beri_debug *bdp, const char *regnump,
	    const char *valuep);
int	berictl_step(struct beri_debug *bdp);
int	berictl_stream_trace(struct beri_debug *bdp, int size, int binary, int version);
int	berictl_print_traces(struct beri_debug *bdp, const char *filep);
int	berictl_pop_trace(struct beri_debug *bdp);
int	berictl_test_run(struct beri_debug *bdp);
int	berictl_test_report(struct beri_debug *bdp);
int	berictl_set_trace_filter(struct beri_debug *bdp);
int	berictl_mem_trace(struct beri_debug *bdp, const char *valuep);

char 	*extract_file(const char *filep, const char *suffix);

#endif /* _CHERICTL_H_ */
