/*-
 * Copyright (c) 2012-2013 Bjoern A. Zeeb
 * All rights reserved.
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

#ifdef __FreeBSD__
#include <sys/endian.h>
#else
#include <endian.h>
#endif

#include <inttypes.h>
#include <stdio.h>
#include <unistd.h>

#ifdef __FreeBSD__
#include <sys/endian.h>
#endif

#include "../../include/cheri_debug.h"
#include "cherictl.h"

static char *
_reg_read32(uint32_t val, char *buf, size_t blen)
{

	return ("");
}

static char *
atse_bitflags_dump(uint32_t val, char *buf, size_t blen, char **fields,
    size_t flen)
{
	int i, n;

	buf[0] = '\0';
	n = 0;
	for (i = 0; i < flen && n < (blen - 4); i++) {
		if (val & (1 << i))
			n += snprintf(buf + n, blen - n, "%s%s",
			    (n > 0) ? "," : " ", fields[i]);
	}
	return (buf);
}

static char *atse_mdio_if_mode[] = {
	"SGMII_ENA",			/* (1<<0) */
	"USE_SGMII_AN",			/* (1<<1) */
	"SGMII_SPEED1",
	"SGMII_SPEED0",
	"SGMII_DUPLEX",
	"Reserved",			/* (1<<5) */
	"Reserved",
	"Reserved",
	"Reserved",
	"Reserved",
	"Reserved",			/* (1<<10) */
	"Reserved",
	"Reserved",
	"Reserved",
	"Reserved",
	"Reserved",			 /* (1<<15) */
};

static char *
_atse_mdio_if_mode(uint32_t val, char *buf, size_t blen)
{

	return (atse_bitflags_dump(val, buf, blen, atse_mdio_if_mode, 16));
}


static char *atse_mdio_partner_ability[] = {
	"Reserved",			/* (1<<0) */
	"Reserved",			/* (1<<1) */
	"Reserved",
	"Reserved",
	"Reserved",
	"1000BASE_X_FD",		/* (1<<5) */
	"1000BASE_X_HD",
	"1000BASE_X_PS1",
	"1000BASE_X_PS2",
	"Reserved",
	"SGMII_COPPER_SPEED0",		/* (1<<10) */
	"SGMII_COPPER_SPEED1",
	"1000BASE_X_RF1/SGMII_COPPER_DUPLEX_STATUS",
	"1000BASE_X_RF2",
	"1000BASE_X_ACK/SGMII_ACK",
	"1000BASE_X_NP/SGMII_COPPER_LINK_STATUS", /* (1<<15) */
};

static char *
_atse_mdio_partner_ability(uint32_t val, char *buf, size_t blen)
{

	return (atse_bitflags_dump(val, buf, blen,
	    atse_mdio_partner_ability, 16));
}

static char *atse_mdio_dev_ability[] = {
	"Reserved",			/* (1<<0) */
	"Reserved",			/* (1<<1) */
	"Reserved",
	"Reserved",
	"Reserved",
	"1000BASE_X_FD",		/* (1<<5) */
	"1000BASE_X_HD",
	"1000BASE_X_PS1",
	"1000BASE_X_PS2",
	"Reserved",
	"Reserved",			/* (1<<10) */
	"Reserved",
	"1000BASE_X_RF1",
	"1000BASE_X_RF2",
	"1000BASE_X_ACK",
	"1000BASE_X_NP",		/* (1<<15) */
};

static char *
_atse_mdio_dev_ability(uint32_t val, char *buf, size_t blen)
{

	return (atse_bitflags_dump(val, buf, blen, atse_mdio_dev_ability, 16));
}

static char *atse_mdio_cmd[] = {
	"Reserved",			/* (1<<0) */
	"Reserved",			/* (1<<1) */
	"Reserved",
	"Reserved",
	"Reserved",
	"UNIDIRECTIONAL_ENABLE",	/* (1<<5) */
	"SPEED_SELECTION6",
	"COLLISION_TEST",
	"DUPLEX_MODE",
	"RESTART_AUTO_NEGOTIATION",
	"ISOLATE",			/* (1<<10) */
	"POWERDOWN",
	"AUTO_NEGOTIATION_ENABLE",
	"SPEED_SELECTION13",
	"LOOPBACK",
	"RESET",			/* (1<<15) */
};

static char *
_atse_mdio_cmd_conf(uint32_t val, char *buf, size_t blen)
{

	return (atse_bitflags_dump(val, buf, blen, atse_mdio_cmd, 16));
}

static char *atse_mdio_status[] = {
	"EXTENDED_CAPABILITY",		/* (1<<0) */
	"JABBER_DETECT",		/* (1<<1) */
	"LINK_STATUS",
	"AUTO_NEGOTIATION_ABILITY",
	"REMOTE_FAULT",
	"AUTO_NEGOTIATION_COMPLETE",	/* (1<<5) */
	"MF_PREAMBLE_SUPPRESSION",
	"UNIDIRECTIONAL_ABILITY",
	"EXTENDED_STATUS",
	"100BASET2_HALF_DUPLEX",
	"100BASET2_FULL_DUPLEX",	/* (1<<10) */
	"10MBPS_HALF_DUPLEX",
	"10MBPS_FULL_DUPLEX",
	"100BASE_X_HALF_DUPLEX",
	"100BASE_X_FULL_DUPLEX",
	"100BASE_T4",			/* (1<<15) */
};

static char *
_atse_mdio_status_conf(uint32_t val, char *buf, size_t blen)
{

	return (atse_bitflags_dump(val, buf, blen, atse_mdio_status, 16));
}

static char *atse_reg_cmd[] = {
	"TX_ENA",			/* (1<<0) */
	"RX_ENA",			/* (1<<1) */
	"XON_GEN",
	"ETH_SPEED",
	"PROMIS_EN",
	"PAD_EN",
	"CRC_FWD",
	"PAUSE_FWD",
	"PAUSE_IGNORE",
	"TX_ADDR_INS",
	"HD_ENA",			/* (1<<10) */
	"EXCESS_COL",
	"LATE_COL",
	"SW_RESET",
	"MHASH_SEL",
	"LOOP_ENA",
	"TX_ADDR_SEL2",
	"TX_ADDR_SEL1",
	"TX_ADDR_SEL0",
	"MAGIC_ENA",
	"SLEEP",			/* (1<<20) */
	"WAKEUP",
	"XOFF_GEN",
	"CNTL_FRM_ENA",
	"NO_LGTH_CHECK",
	"ENA_10",
	"RX_ERR_DISC",
	"DISABLE_READ_TIMEOUT",		/* (1<<27) */
	"Reserved",
	"Reserved",
	"Reserved",
	"CNT_RESET"			/* (1<<31) */
};

static char *
atse_reg_cmd_conf(uint32_t val, char *buf, size_t blen)
{

	return (atse_bitflags_dump(val, buf, blen, atse_reg_cmd, 32));
}

static char *
atse_reg_nop(uint32_t val, char *buf, size_t blen)
{

	return ("");
}

static struct atse_regs {
	const char		*reg_name;
	char			*(*reg_print)(uint32_t, char *, size_t);
} atse_regs[] = {
/* Base Configuration Registers */
{ "rev",				_reg_read32 },	/* 0x00 */
{ "scratch(1)",				_reg_read32 },	/* 0x01 */
{ "command config",			atse_reg_cmd_conf },	/* 0x02 */
{ "mac_0",				_reg_read32 },	/* 0x03 */
{ "mac_1",				_reg_read32 },	/* 0x04 */
{ "frm_length",				_reg_read32 },	/* 0x05 */
{ "pause_quant",			_reg_read32 },	/* 0x06 */
{ "rx_section_empty",			_reg_read32 },	/* 0x07 */
{ "rx_section_full",			_reg_read32 },	/* 0x08 */
{ "tx_section_empty",			_reg_read32 },	/* 0x09 */
{ "tx_section_full",			_reg_read32 },	/* 0x0a */
{ "rx_almost_empty",			_reg_read32 },	/* 0x0b */
{ "rx_almost_full",			_reg_read32 },	/* 0x0c */
{ "tx_almost_empty",			_reg_read32 },	/* 0x0d */
{ "tx_almost_full",			_reg_read32 },	/* 0x0e */
{ "mdio_addr0",		 		_reg_read32 },	/* 0x0f */
{ "mdio_addr1",		 		_reg_read32 },	/* 0x10 */
{ "holdoff_quant",			_reg_read32 },	/* 0x11 */
{ "Reserved",				atse_reg_nop },		/* 0x12 */
{ "Reserved",				atse_reg_nop },		/* 0x13 */
{ "Reserved",				atse_reg_nop },		/* 0x14 */
{ "Reserved",				atse_reg_nop },		/* 0x15 */
{ "Reserved",				atse_reg_nop },		/* 0x16 */
{ "tx_ipg_length",			_reg_read32 },	/* 0x17 */
/* Statistics Counters */
{ "aMacID_0",				_reg_read32 },	/* 0x18 */
{ "aMacID_1",				_reg_read32 },
{ "aFramesTransmittedOK",		_reg_read32 },
{ "aFramesReceivedOK",			_reg_read32 },
{ "aFrameCheckSequenceErrors",		_reg_read32 },
{ "aAlignmentErrors",			_reg_read32 },
{ "aOctetsTransmittedOK",		_reg_read32 },
{ "aOctetsReceivedOK",			_reg_read32 },
{ "aTxPAUSEMACCtrlFrames",		_reg_read32 },
{ "aRxPAUSEMACCtrlFrames",		_reg_read32 },
{ "ifInErrors",				_reg_read32 },
{ "ifOutErrors",			_reg_read32 },
{ "ifInUcastPkts",			_reg_read32 },
{ "ifInMulticastPkts",			_reg_read32 },
{ "ifInBroadcastPkts",			_reg_read32 },
{ "ifOutDiscards",			_reg_read32 },
{ "ifOutUcastPkts",			_reg_read32 },
{ "ifOutMulticastPkts",			_reg_read32 },
{ "ifOutBroadcastPkts",			_reg_read32 },
{ "etherStatsDropEvents",		_reg_read32 },
{ "etherStatsOctets",			_reg_read32 },
{ "etherStatsPkts",			_reg_read32 },
{ "etherStatsUndersizePkts",		_reg_read32 },
{ "etherStatsOversizePkts",		_reg_read32 },
{ "etherStatsPkts64Octets",		_reg_read32 },
{ "etherStatsPkts65to127Octets",	_reg_read32 },
{ "etherStatsPkts128to255Octets",	_reg_read32 },
{ "etherStatsPkts256to511Octets",	_reg_read32 },
{ "etherStatsPkts512to1023Octets",	_reg_read32 },
{ "etherStatsPkts1024to1518Octets",	_reg_read32 },
{ "etherStatsPkts1519toXOctets",	_reg_read32 },
{ "etherStatsJabbers",			_reg_read32 },
{ "etherStatsFragments",		_reg_read32 },	/* 0x38 */
{ "Reserved",				atse_reg_nop },		/* 0x39 */
/* Transmit and Receive Command Registers */
{ "tx_cmd_stat",			_reg_read32 },	/* 0x3a */
{ "rx_cmd_stat",			_reg_read32 },	/* 0x3b */
/* Extended Statistics Counters */
{ "msb_aOctetsTransmittedOK",		_reg_read32 },	/* 0x3c */
{ "msb_aOctetsReceivedOK",		_reg_read32 },	/* 0x3d */
{ "msb_etherStatsOctets",		_reg_read32 },	/* 0x3e */
{ "Reserved",				atse_reg_nop },		/* 0x3f */
/* Multicast Hash Table */
{ "MCHashTable_00",			_reg_read32 },	/* 0x40 */
{ "MCHashTable_01",			_reg_read32 },
{ "MCHashTable_02",			_reg_read32 },
{ "MCHashTable_03",			_reg_read32 },
{ "MCHashTable_04",			_reg_read32 },
{ "MCHashTable_05",			_reg_read32 },
{ "MCHashTable_06",			_reg_read32 },
{ "MCHashTable_07",			_reg_read32 },
{ "MCHashTable_08",			_reg_read32 },
{ "MCHashTable_09",			_reg_read32 },
{ "MCHashTable_0a",			_reg_read32 },
{ "MCHashTable_0b",			_reg_read32 },
{ "MCHashTable_0c",			_reg_read32 },
{ "MCHashTable_0d",			_reg_read32 },
{ "MCHashTable_0e",			_reg_read32 },
{ "MCHashTable_0f",			_reg_read32 },
{ "MCHashTable_10",			_reg_read32 },	/* 0x50 */
{ "MCHashTable_11",			_reg_read32 },
{ "MCHashTable_12",			_reg_read32 },
{ "MCHashTable_13",			_reg_read32 },
{ "MCHashTable_14",			_reg_read32 },
{ "MCHashTable_15",			_reg_read32 },
{ "MCHashTable_16",			_reg_read32 },
{ "MCHashTable_17",			_reg_read32 },
{ "MCHashTable_18",			_reg_read32 },
{ "MCHashTable_19",			_reg_read32 },
{ "MCHashTable_1a",			_reg_read32 },
{ "MCHashTable_1b",			_reg_read32 },
{ "MCHashTable_1c",			_reg_read32 },
{ "MCHashTable_1d",			_reg_read32 },
{ "MCHashTable_1e",			_reg_read32 },
{ "MCHashTable_1f",			_reg_read32 },
{ "MCHashTable_20",			_reg_read32 },	/* 0x60 */
{ "MCHashTable_21",			_reg_read32 },
{ "MCHashTable_22",			_reg_read32 },
{ "MCHashTable_23",			_reg_read32 },
{ "MCHashTable_24",			_reg_read32 },
{ "MCHashTable_25",			_reg_read32 },
{ "MCHashTable_26",			_reg_read32 },
{ "MCHashTable_27",			_reg_read32 },
{ "MCHashTable_28",			_reg_read32 },
{ "MCHashTable_29",			_reg_read32 },
{ "MCHashTable_2a",			_reg_read32 },
{ "MCHashTable_2b",			_reg_read32 },
{ "MCHashTable_2c",			_reg_read32 },
{ "MCHashTable_2d",			_reg_read32 },
{ "MCHashTable_2e",			_reg_read32 },
{ "MCHashTable_2f",			_reg_read32 },
{ "MCHashTable_30",			_reg_read32 },	/* 0x70 */
{ "MCHashTable_31",			_reg_read32 },
{ "MCHashTable_32",			_reg_read32 },
{ "MCHashTable_33",			_reg_read32 },
{ "MCHashTable_34",			_reg_read32 },
{ "MCHashTable_35",			_reg_read32 },
{ "MCHashTable_36",			_reg_read32 },
{ "MCHashTable_37",			_reg_read32 },
{ "MCHashTable_38",			_reg_read32 },
{ "MCHashTable_39",			_reg_read32 },
{ "MCHashTable_3a",			_reg_read32 },
{ "MCHashTable_3b",			_reg_read32 },
{ "MCHashTable_3c",			_reg_read32 },
{ "MCHashTable_3d",			_reg_read32 },
{ "MCHashTable_3e",			_reg_read32 },
{ "MCHashTable_3f",			_reg_read32 },
/* MDIO Space 0 or PCS Function Configuration */
{ "MDIO_0_PCS Control Register", 	_atse_mdio_cmd_conf },	/* 0x80 */
{ "MDIO_0_PCS Status Register",		_atse_mdio_status_conf },
{ "MDIO_0_PCS_02",			_reg_read32 },
{ "MDIO_0_PCS_03",			_reg_read32 },
{ "MDIO_0_PCS Device Ability",		_atse_mdio_dev_ability },
{ "MDIO_0_PCS Partner Ability",		_atse_mdio_partner_ability },
{ "MDIO_0_PCS_06",			_reg_read32 },
{ "MDIO_0_PCS_07",			_reg_read32 },
{ "MDIO_0_PCS_08",			_reg_read32 },
{ "MDIO_0_PCS_09",			_reg_read32 },
{ "MDIO_0_PCS_0a",			_reg_read32 },
{ "MDIO_0_PCS_0b",			_reg_read32 },
{ "MDIO_0_PCS_0c",			_reg_read32 },
{ "MDIO_0_PCS_0d",			_reg_read32 },
{ "MDIO_0_PCS_0e",			_reg_read32 },
{ "MDIO_0_PCS_0f",			_reg_read32 },
{ "MDIO_0_PCS_10",		 	_reg_read32 },	/* 0x90 */
{ "MDIO_0_PCS_11",			_reg_read32 },
{ "MDIO_0_PCS_12",			_reg_read32 },
{ "MDIO_0_PCS_13",			_reg_read32 },
{ "MDIO_0 Interface Mode",		_atse_mdio_if_mode },
{ "MDIO_0_PCS_15",			_reg_read32 },
{ "MDIO_0_PCS_16",			_reg_read32 },
{ "MDIO_0_PCS_17",			_reg_read32 },
{ "MDIO_0_PCS_18",			_reg_read32 },
{ "MDIO_0_PCS_19",			_reg_read32 },
{ "MDIO_0_PCS_1a",			_reg_read32 },
{ "MDIO_0_PCS_1b",			_reg_read32 },
{ "MDIO_0_PCS_1c",			_reg_read32 },
{ "MDIO_0_PCS_1d",			_reg_read32 },
{ "MDIO_0_PCS_1e",			_reg_read32 },
{ "MDIO_0_PCS_1f",			_reg_read32 },
/* MDIO Space 1 */
{ "MDIO_1 Control Register",	 	_atse_mdio_cmd_conf },	/* 0xa0 */
{ "MDIO_1 Status Register",		_atse_mdio_status_conf },
{ "MDIO_1_02",				_reg_read32 },
{ "MDIO_1_03",				_reg_read32 },
{ "MDIO_1 Device Ability",		_atse_mdio_dev_ability },
{ "MDIO_1 Partner Ability",		_atse_mdio_partner_ability },
{ "MDIO_1_06",				_reg_read32 },
{ "MDIO_1_07",				_reg_read32 },
{ "MDIO_1_08",				_reg_read32 },
{ "MDIO_1_09",				_reg_read32 },
{ "MDIO_1_0a",				_reg_read32 },
{ "MDIO_1_0b",				_reg_read32 },
{ "MDIO_1_0c",				_reg_read32 },
{ "MDIO_1_0d",				_reg_read32 },
{ "MDIO_1_0e",				_reg_read32 },
{ "MDIO_1_0f",				_reg_read32 },
{ "MDIO_1_10",			 	_reg_read32 },	/* 0xb0 */
{ "MDIO_1_11",				_reg_read32 },
{ "MDIO_1_12",				_reg_read32 },
{ "MDIO_1_13",				_reg_read32 },
{ "MDIO_1 Interface Mode",		_atse_mdio_if_mode },
{ "MDIO_1_15",				_reg_read32 },
{ "MDIO_1_16",				_reg_read32 },
{ "MDIO_1_17",				_reg_read32 },
{ "MDIO_1_18",				_reg_read32 },
{ "MDIO_1_19",				_reg_read32 },
{ "MDIO_1_1a",				_reg_read32 },
{ "MDIO_1_1b",				_reg_read32 },
{ "MDIO_1_1c",				_reg_read32 },
{ "MDIO_1_1d",				_reg_read32 },
{ "MDIO_1_1e",				_reg_read32 },
{ "MDIO_1_1f",				_reg_read32 },
/* Supplementary Address */
{ "smac_0_0",				_reg_read32 },	/* 0xc0 */
{ "smac_0_1",				_reg_read32 },
{ "smac_1_0",				_reg_read32 },
{ "smac_1_1",				_reg_read32 },
{ "smac_2_0",				_reg_read32 },
{ "smac_2_1",				_reg_read32 },
{ "smac_3_0",				_reg_read32 },
{ "smac_3_1",				_reg_read32 },
/* Reserved */
{ "Reserved",				atse_reg_nop },		/* 0xc8 */
{ "Reserved",				atse_reg_nop },		/* 0xc9 */
{ "Reserved",				atse_reg_nop },		/* 0xca */
{ "Reserved",				atse_reg_nop },		/* 0xcb */
{ "Reserved",				atse_reg_nop },		/* 0xcc */
{ "Reserved",				atse_reg_nop },		/* 0xcd */
{ "Reserved",				atse_reg_nop },		/* 0xce */
{ "Reserved",				atse_reg_nop },		/* 0xcf */
/* Undefined? */
{ "Undefined?",				atse_reg_nop },		/* 0xd0 */
{ "Undefined?",				atse_reg_nop },		/* 0xd1 */
{ "Undefined?",				atse_reg_nop },		/* 0xd2 */
{ "Undefined?",				atse_reg_nop },		/* 0xd3 */
{ "Undefined?",				atse_reg_nop },		/* 0xd4 */
{ "Undefined?",				atse_reg_nop },		/* 0xd5 */
{ "Undefined?",				atse_reg_nop },		/* 0xd6 */
/* Reserved */
{ "Reserved",				atse_reg_nop },		/* 0xd7 */
{ "Reserved",				atse_reg_nop },		/* 0xd8 */
{ "Reserved",				atse_reg_nop },		/* 0xd9 */
{ "Reserved",				atse_reg_nop },		/* 0xda */
{ "Reserved",				atse_reg_nop },		/* 0xdb */
{ "Reserved",				atse_reg_nop },		/* 0xdc */
{ "Reserved",				atse_reg_nop },		/* 0xdd */
{ "Reserved",				atse_reg_nop },		/* 0xde */
{ "Reserved",				atse_reg_nop },		/* 0xdf */
{ "Reserved",				atse_reg_nop },		/* 0xe0 */
{ "Reserved",				atse_reg_nop },		/* 0xe1 */
{ "Reserved",				atse_reg_nop },		/* 0xe2 */
{ "Reserved",				atse_reg_nop },		/* 0xe3 */
{ "Reserved",				atse_reg_nop },		/* 0xe4 */
{ "Reserved",				atse_reg_nop },		/* 0xe5 */
{ "Reserved",				atse_reg_nop },		/* 0xe6 */
{ "Reserved",				atse_reg_nop },		/* 0xe7 */
{ "Reserved",				atse_reg_nop },		/* 0xe8 */
{ "Reserved",				atse_reg_nop },		/* 0xe9 */
{ "Reserved",				atse_reg_nop },		/* 0xea */
{ "Reserved",				atse_reg_nop },		/* 0xeb */
{ "Reserved",				atse_reg_nop },		/* 0xec */
{ "Reserved",				atse_reg_nop },		/* 0xed */
{ "Reserved",				atse_reg_nop },		/* 0xee */
{ "Reserved",				atse_reg_nop },		/* 0xef */
{ "Reserved",				atse_reg_nop },		/* 0xf0 */
{ "Reserved",				atse_reg_nop },		/* 0xf1 */
{ "Reserved",				atse_reg_nop },		/* 0xf2 */
{ "Reserved",				atse_reg_nop },		/* 0xf3 */
{ "Reserved",				atse_reg_nop },		/* 0xf4 */
{ "Reserved",				atse_reg_nop },		/* 0xf5 */
{ "Reserved",				atse_reg_nop },		/* 0xf6 */
{ "Reserved",				atse_reg_nop },		/* 0xf7 */
{ "Reserved",				atse_reg_nop },		/* 0xf8 */
{ "Reserved",				atse_reg_nop },		/* 0xf9 */
{ "Reserved",				atse_reg_nop },		/* 0xfa */
{ "Reserved",				atse_reg_nop },		/* 0xfb */
{ "Reserved",				atse_reg_nop },		/* 0xfc */
{ "Reserved",				atse_reg_nop },		/* 0xfd */
{ "Reserved",				atse_reg_nop },		/* 0xfe */
{ "Reserved",				atse_reg_nop },		/* 0xff */
};

int
berictl_dumpatse(struct beri_debug *bdp, const char *addrp)
{
#ifndef	LINE_MAX
#define	LINE_MAX	2048
#endif
	char buf[LINE_MAX];
	uint64_t addr;
	uint32_t v;
	int i, ret;
	uint8_t excode;

	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);
	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	if (!quietflag)
		printf("atse(4) control registers:\n");

	/* Pause CPU */
	ret = berictl_pause(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

#if 0
#define	ATSE_MAC_CONF_LEN       0xff            /* Incl. resevered space. */
#undef ATSE_MAC_CONF_LEN
#define	ATSE_MAC_CONF_LEN       0x7f
#undef ATSE_MAC_CONF_LEN
#define	ATSE_MAC_CONF_LEN       0xc7
#undef ATSE_MAC_CONF_LEN
#define	ATSE_MAC_CONF_LEN	0x3f
#undef ATSE_MAC_CONF_LEN
#endif
#define	ATSE_MAC_CONF_LEN	0xff
	for (i = 0; ret == BERI_DEBUG_SUCCESS && i <= ATSE_MAC_CONF_LEN; i++) {
		ret = beri_debug_client_lwu(bdp, htobe64(addr), &v, &excode);
		switch (ret) {
		case BERI_DEBUG_ERROR_EXCEPTION:
			fprintf(stderr, "0x%02x 0x%016jx Exception!  "
			    "Code = 0x%x\n", i, addr, excode);
			break;
		case BERI_DEBUG_SUCCESS:
			v = be32toh(v);
			printf("0x%02x 0x%016jx = 0x%08x (%s%s)\n", i, addr, v,
			    atse_regs[i].reg_name,
			    (*atse_regs[i].reg_print)(v, buf, sizeof(buf)));
			break;
		}
		addr += 4;
	}

	/* Resume CPU */
	if (berictl_resume(bdp) != BERI_DEBUG_SUCCESS) {
		fprintf(stderr, "Resuming CPU failed. You are screwed.\n");
		ret = BERI_DEBUG_ERROR_EXCEPTION;
	}

	return (ret);
}


static char *
fifo_read_conf1(uint32_t val, char *buf, size_t blen)
{
	int n;

	buf[0] = '\0';
	n = 0;

	if (val & 0x00000001)
		n += snprintf(buf + n, blen - n, "%s%s", (n > 0) ? "," : " ",
		    "SOP");
	if (val & 0x00000002)
		n += snprintf(buf + n, blen - n, "%s%s", (n > 0) ? "," : " ",
		    "EOP");
	n += snprintf(buf + n, blen - n, "%sEMPTY 0x%02x", (n > 0) ? "," : " ",
	    (val >> 2) & 0x0f);
	n += snprintf(buf + n, blen - n, "%sCHANNEL 0x%02x", (n > 0) ? "," : " ",
	    (val >> 8) & 0xff);
	n += snprintf(buf + n, blen - n, "%sERROR 0x%02x", (n > 0) ? "," : " ",
	    (val >> 16) & 0xff);

	return (buf);
}

static struct fifo_regs {
	uint64_t		offset;
	const char		*reg_name;
	char			*(*reg_print)(uint32_t, char *, size_t);
} fifo_regs[] = {
	/* 0x00, Memory Map */
	/* 0x00, Cannot touch data unless we can risk hangs. */
	{ 0x04, "conf 1",	fifo_read_conf1 },
	/* 0x20, Status Register */
	{ 0x20, "fill_level",	_reg_read32 },
	{ 0x24, "i_status",	_reg_read32 },
	{ 0x28, "event",	_reg_read32 },
	{ 0x2c, "intr enable",	_reg_read32 },
	{ 0x30, "almostfull",	_reg_read32 },
	{ 0x34, "almostempty",	_reg_read32 },
};

int
berictl_dumpfifo(struct beri_debug *bdp, const char *addrp)
{
#ifndef	LINE_MAX
#define	LINE_MAX	2048
#endif
	char buf[LINE_MAX];
	uint64_t addr;
	uint32_t v;
	int i, ret;
	uint8_t excode;

	if (addrp == NULL)
		return (BERI_DEBUG_USAGE_ERROR);
	ret = hex2addr(addrp, &addr);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	if (!quietflag)
		printf("fifo status and meta data registers:\n");

	/* Pause CPU */
	ret = berictl_pause(bdp);
	if (ret != BERI_DEBUG_SUCCESS)
		return (ret);

	for (i = 0; ret == BERI_DEBUG_SUCCESS &&
	    i < sizeof(fifo_regs)/sizeof(*fifo_regs); i++) {
		ret = beri_debug_client_lwu(bdp,
		    htobe64(addr + fifo_regs[i].offset), &v, &excode);
		switch (ret) {
		case BERI_DEBUG_ERROR_EXCEPTION:
			fprintf(stderr, "0x%02x 0x%016jx Exception!  "
			    "Code = 0x%x\n", i, addr, excode);
			break;
		case BERI_DEBUG_SUCCESS:
			v = be32toh(v);
			printf("0x%02x 0x%016jx = 0x%08x (%s%s)\n",
			    i, (addr + fifo_regs[i].offset), v,
			    fifo_regs[i].reg_name,
			    (*fifo_regs[i].reg_print)(v, buf, sizeof(buf)));
			break;
		}
	}

	/* Resume CPU */
	if (berictl_resume(bdp) != BERI_DEBUG_SUCCESS) {
		fprintf(stderr, "Resuming CPU failed. You are screwed.\n");
		ret = BERI_DEBUG_ERROR_EXCEPTION;
	}

	return (ret);
}

/* end */
