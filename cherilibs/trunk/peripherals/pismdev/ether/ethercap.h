/*-
 * Copyright (c) 2011 Wojciech A. Koszek
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
#ifndef	_ETHERCAP_H_
#define	_ETHERCAP_H_

#define	TAP_DEVPATH	"/dev/net/tun"

struct cheri_net_data {
	char	*chnd_data;
	int	chnd_datasize;
	int	chnd_dataidx;
};
typedef struct cheri_net_data	cheri_net_data_t;

/*
 * Standard data buffer size for CHERI networking.
 */
#define	CHERI_NET_DATABUF_SIZE	1024

struct cheri_net;
/*
 * Interface for network adapter emulation.
 */
typedef uint32_t	adapter_func_t(struct cheri_net *chnp, uint32_t addr,
				uint32_t data, uint32_t acctype);
typedef int		adapter_init_t(struct cheri_net *chnp);
struct adapter {
	adapter_init_t	*adp_init;
	adapter_func_t	*adp_func;
};
typedef struct adapter	adapter_t;

struct cheri_net {
	int	chn_fd;
	char	chn_ifname[16];
	int	chn_flags;

	adapter_t	*adpp;
	uint32_t	 adp_regfile[0xffff];

	cheri_net_data_t	chn_rx;
	cheri_net_data_t	chn_tx;
};
typedef struct cheri_net	cheri_net_t;

/*
 * Relatively decent failover option in case of CHERI_NET_SCRIPT being undefined.
 */
#define	CHERI_NET_SCRIPT_DEFAULT	"./cheri_net_setup.sh"

/*
 * Flags for chn_flags field.
 */
#define	CHERI_NET_STARTED	(1 << 0)

extern uint64_t	g_debug_mask;

static inline void
cheri_dbg(uint64_t flag, const char *fmt, ...)
{
	va_list	va;

	if (g_debug_mask & flag) {
		va_start(va, fmt);
		printf("%s(%d): ", __func__, __LINE__);
		vprintf(fmt, va);
		printf("\n");
		va_end(va);
	}
}
#define	DBG_TX_FLAG	(1<<0)
#define	DBG_RX_FLAG	(1<<1)
#define	TXDBG(...)	cheri_dbg(DBG_TX_FLAG, __VA_ARGS__)
#define	RXDBG(...)	cheri_dbg(DBG_RX_FLAG, __VA_ARGS__)

uint32_t	cheri_net_data_crc(cheri_net_data_t *chnd);
#endif /* _ETHERCAP_H_ */
