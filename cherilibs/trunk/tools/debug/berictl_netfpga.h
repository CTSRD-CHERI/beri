/*-
 * Copyright (c) 2013-2014 Bjoern A. Zeeb
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

#ifndef	_BERICTL_NETFPGA_H
#define	_BERICTL_NETFPGA_H

#ifdef BERI_NETFPGA
#define	NETFPGA_DEV_PATH			"/dev/nf10"
#ifdef __linux__
#ifndef NETFPGA_IOCTL_CMD_WRITE_REG
#define	NETFPGA_IOCTL_CMD_WRITE_REG		(SIOCDEVPRIVATE+1)
#endif
#ifndef NETFPGA_IOCTL_CMD_READ_REG
#define	NETFPGA_IOCTL_CMD_READ_REG		(SIOCDEVPRIVATE+2)
#endif
#elif __FreeBSD__
/* Make something up for now. */
#define NETFPGA_IOCTL_CMD_WRITE_REG		_IOW('Y', 241, int)
#define NETFPGA_IOCTL_CMD_READ_REG		_IOW('Y', 242, int)
#else
#error NetFPGA ioctls unsupported
#endif
#define	NETFPGA_IOCTL_PAYLOAD_MAX		1024
#define	NETFPGA_AXI_DEBUG_BRIDGE_BASE_ADDR	0x80004000
#define	NETFPGA_AXI_DEBUG_BRIDGE_WR_GO				\
	(NETFPGA_AXI_DEBUG_BRIDGE_BASE_ADDR + 0x08)
#define	NETFPGA_AXI_DEBUG_BRIDGE_WR				\
	(NETFPGA_AXI_DEBUG_BRIDGE_BASE_ADDR + 0x20)
#define	NETFPGA_AXI_DEBUG_BRIDGE_RD				\
	(NETFPGA_AXI_DEBUG_BRIDGE_BASE_ADDR + 0x24)
#define	NETFPGA_AXI_JTAG_UART_BASE_ADDR		0x7f000100
#define	NETFPGA_AXI_FIFO_RD_BYTE_VALID		0x01000000
#define	NETFPGA_AXI_FIFO_RD_BYTE_VALID_CONS	0x80000000
#define	NETFPGA_IOCTL_WR(r, v)					\
	do {							\
		uint64_t rv;					\
		int ret;					\
								\
		assert(((v) & 0xffffff00) == 0);		\
		rv = ((uint64_t)(r) << 32) | ((v) & 0xff);	\
		ret = ioctl(bdp->bd_fd, NETFPGA_IOCTL_CMD_WRITE_REG, rv); \
		if (ret == -1)					\
			return (BERI_DEBUG_ERROR_SEND);	\
	} while (0)
#define	NETFPGA_IOCTL_RD(rv, r)					\
	do {							\
		int ret;					\
								\
		/* GRR asymmetric ioctls; rv = ((uint64_t)(r) << 32); */ \
		rv = (uint64_t)(r);				\
		ret = ioctl(bdp->bd_fd, NETFPGA_IOCTL_CMD_READ_REG, &rv); \
		if (ret == -1)					\
			return (BERI_DEBUG_ERROR_READ);	\
		rv &= 0xffffffff;				\
	} while ((rv & NETFPGA_AXI_FIFO_RD_BYTE_VALID) !=	\
	    NETFPGA_AXI_FIFO_RD_BYTE_VALID)
#endif /* BERI_NETFPGA */

#endif /* _BERICTL_NETFPGA_H */
