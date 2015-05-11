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
/*
 * Quickstart on how to run this test program:
 * 
 * env CHERI_NET_DEV=tap0 CHERI_NET_SCRIPT=`pwd`/cheri_net_setup.sh ./test -ddd -w 128 -N 100
 *
 * This will write 100 frames of 128 bytes each with excessive debugging (-ddd)
 * to tap0 device, which will be created by this program but configured by
 * cheri_net_setup.sh.
 *
 * Details on implementation
 *
 * Cheri networking state is represented by ''cheri_net_t'' data structure. Its
 * main members are RX and TX queues (''cheri_net_data_t'') for receiving and
 * transmiting data respectively. All the structures are hidden in the
 * background and provide the convenient way on dealing with network
 * sending/receiving and pushing data to the Bluespec side of world.
 *
 * adapter_t represents adapter abstraction. This is how we provide
 * adapter-specific API. Currently you have 2 adapter's routines -
 * initialization routine and handler routine. Initialization routine
 * initialized register space for the adapter and sets read-only/constant
 * register values. Adapter's handler routine simulates exact adapter
 * behaviour.
 *
 * In the current implementation there's one cheri_net_t structure called
 * ''g_cheri_net_bsv'', but all C API calls take cheri_net_t explicitly, so
 * enhancements to this are possible (if necessary).
 *
 * Bluespec accesses C layer present in this file with cheri_net_handler().  In
 * case of access being the first, ''g_cheri_net_bsv'' will be initialized.
 * otherwise, the access will be passed to the adapter-specific handling
 * routine.
 *
 * In the first case, cheri_net_start() is called. Within this routine, tap
 * device gets created, network setup is called (from within which bridged
 * networking should get started) and data buffers are initialized. Adapter
 * register space is initialized in this routine too. Current implementation
 * calls smc_init() from this function.
 *
 * In the later case, when the network structures are already being initialized
 * (non-first access), memory access (performed with cheri_net_handler()) is
 * being forwarded to the adapter-specific routine. In the current
 * implementation, only one adapter (SMSC9115) is supported. The adapter's
 * handler is implemented in smc_handler() function.
 *
 * smc_handler() makes use of 'faked register' array of 32-bit unsigned
 * integers.  Array is present in cheri_net_t, since it's assumed that every
 * adapter will require some space for its registers. Exact implementation
 * of the handler isn't explained here, but smc_handler() has appropriate comments.
 *
 * The only important fact about smc_handler() is that it's responsible for calling
 * cheri_net_poll() which should move data received on tap interface to RX queue
 * and transmit data from TX queue to the tap device. It's adapter's dependent
 * behaviour on when it's supposed to happen.
 *
 * Simulation process
 *
 * 'test' program can be built with 'make test'. Running the test, in
 * successful case, should result in data being sent over the network and data
 * should get received from the network. For exact details on usage, see
 * usage().
 *
 * Remember that Ethernet interface must be configured on both sending (we) and
 * receiving side. The most important: remember to set an IP address of the
 * receiving interface. Otherwise link is down, which isn't shown in Linux
 * ifconfig(8). You must use ethtool(8) to diagnose that.
 *
 * Following code uses FreeBSD style(9) with following exceptions: 2nd level
 * indention is tab-spaced and even single-statement blocks are surrounded with
 * brackets. Global variables are prefixed with g_.
 */
#define _BSD_SOURCE
#define _XOPEN_SOURCE 

#include <sys/param.h>
#include <sys/queue.h>
#include <features.h>

#include <net/if.h>
#include <sys/ioctl.h>
#include <arpa/inet.h>

#include <linux/if_tun.h>

#include <assert.h>
#include <err.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <poll.h>

#include "pismdev/ether/ethercap.h"
#include "pismdev/pism.h"
#include "pismdev/cheri.h"

#define	NRD(addr)	cheri_net_handler((addr), (0), 1)
#define	NWR(addr, data)	cheri_net_handler((addr), (data), 0)

static adapter_func_t	smc_handler;
static adapter_init_t	smc_init;
static adapter_t	smc = { smc_init, smc_handler };
static adapter_t *adapters[] = {
	&smc,
};

/*
 * Global state of the CHERI networking for the functions exported to Bluespec
 * This should only be used by cheri_net_*_bsv(...) functions.
 */
cheri_net_t	g_cheri_net_bsv;

/*
 * Is the network initialized?
 */
static int	g_cheri_net_inited = 0;

/*
 * Debug mask.
 */
uint64_t	g_debug_mask = 0;

/*
 * Initialize CHERI network buffer.
 */
int
cheri_net_data_init(cheri_net_data_t *chnd, int size)
{

	assert(chnd != NULL);
	assert(size > 0);

	memset(chnd, 0, sizeof(*chnd));
	chnd->chnd_data = calloc(size, 1);
	if (chnd->chnd_data == NULL) {
		return (-__LINE__);
	}
	chnd->chnd_datasize = size;
	chnd->chnd_dataidx = 0;
	return 0;
}

/*
 * Destroy and release CHERI network data buffer.
 */
void
cheri_net_data_destroy(cheri_net_data_t *chnd)
{
	char	*data;

	assert(chnd != NULL);
	assert(chnd->chnd_data != NULL);

	data = chnd->chnd_data;
	memset(chnd, 0x55, sizeof(*chnd));
	free(data);
}

/*
 * Put data into CHERI network data buffer.
 */
int
cheri_net_data_put(cheri_net_data_t *chnd, uint32_t *data, int len)
{

	assert(chnd != NULL);
	assert(data != NULL);
	assert(len > 0);

	if ((chnd->chnd_dataidx + len) >= chnd->chnd_datasize) {
		return (-__LINE__);
	}
	memcpy(chnd->chnd_data + chnd->chnd_dataidx, data, len);
	chnd->chnd_dataidx += len;
	return 0;
}

/*
 * Get data from CHERI network data buffer.
 */
int
cheri_net_data_get(cheri_net_data_t *chnd, uint32_t *rdata, int len)
{

	if (chnd->chnd_dataidx < len) {
		return (-__LINE__);
	}
	memcpy(rdata, chnd->chnd_data, len);
	chnd->chnd_dataidx -= len;
	return 0;
}

/*
 * Get number of bytes of data.
 */
int
cheri_net_data_size(cheri_net_data_t *chnd)
{

	return (chnd->chnd_dataidx);
}

/*
 * Print data.
 */
static void
cheri_net_data_inspect(cheri_net_data_t *chnd, const char *comment)
{
	int	howmany, i, nonzero, wantnl, val, valsum;
	char	*buf;

	buf = chnd->chnd_data;
	howmany = chnd->chnd_dataidx;
	printf("=== %s ===\n", comment);
	printf("BufSize: %d\n", howmany);
	valsum = 0;
	for (i = 0; i < howmany; i++) {
		val = buf[i];
		valsum += val;
		wantnl = (((i + 1) % 6) == 0);
		nonzero = (wantnl == 1) && (valsum != 0);
		printf("0x%02hhx %s %s", val,
			(nonzero ? "nonzero" : ""),
			(wantnl ? "\n" : "")
		);
		if (wantnl) {
			valsum = 0;
		}
	}
	printf("\n");
}

/*
 * Print data.
 */
uint32_t
cheri_net_data_crc(cheri_net_data_t *chnd)
{
	uint32_t crc;
	int	howmany, i;
	char	*buf;

	buf = chnd->chnd_data;
	howmany = chnd->chnd_dataidx;
	crc = 0;
	for (i = 0; i < howmany; i++) {
		crc += buf[i];
	}
	return crc;
}

/*
 * Start CHERI networking.
 */
static int
cheri_net_start(cheri_net_t *chn, const char *iname)
{
	struct ifreq ifr;
	char *setuppath;
	char setupcmd[MAXPATHLEN * 2];
	int error, fd;

	assert(chn != NULL);
	if ((chn->chn_flags & CHERI_NET_STARTED) && (chn->chn_fd > 0)) {
		/*
		 * Don't try to initialize network twice.
		 */
		return 0;
	}
	chn->adpp = adapters[0];
	assert(chn->adpp != NULL);
	memset(chn->adp_regfile, 0, sizeof(chn->adp_regfile));
	if (chn->adpp->adp_init != NULL) {
		error = chn->adpp->adp_init(chn);
		assert(error == 0 && "adapter couldn't be initialized");
	}

	/* Let non-root users run adapter simulation */
	if ((getuid() != 0) && (geteuid() != 0)) {
		printf("\n\tUID != 0, Adapter simulation only!!\n\n");
		return 0;
	}

	fd = open(TAP_DEVPATH, O_RDWR);
	if (fd == -1) {
		return (-__LINE__);
	}
	memset(&ifr, 0, sizeof(ifr));
	ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
	snprintf(ifr.ifr_name, sizeof(ifr.ifr_name) - 1, "%s", iname);
	error = ioctl(fd, TUNSETIFF, (void *)&ifr);
	if (error != 0) {
		return (-__LINE__);
	}

	/*
	 * XX: my assumption is that we're ready to always the simulation environment
	 *   be trusted. In other words, while getenv() + system() would normally mean
	 *   asking for trouble, I assume we'll be always running by users who know
	 *   what they're doing
	 */
	setuppath = getenv("CHERI_NET_SCRIPT");
	if (setuppath == NULL) {
		error = access(CHERI_NET_SCRIPT_DEFAULT, X_OK|F_OK);
		if (error == 0) {
			setuppath = CHERI_NET_SCRIPT_DEFAULT;
		}
	}
	if (setuppath == NULL) {
		fprintf(stderr, "You must set CHERI_NET_SCRIPT environment"
			"variable in order to get CHERI networking to work.\n");
		abort();
	}
	error = access(setuppath, X_OK | F_OK);	/* Just in case.. */
	if (error != 0) {
		fprintf(stderr, "Problem with '%s': %s\n", setuppath,
			strerror(errno));
		abort();
	}
	snprintf(setupcmd, sizeof(setupcmd), "%s", setuppath);
	error = system(setupcmd);
	assert(error == 0);

	chn->chn_fd = fd;
	chn->chn_flags = CHERI_NET_STARTED;
	snprintf(chn->chn_ifname, sizeof(chn->chn_ifname) - 1, "%s",
		ifr.ifr_name);
	assert(strcmp(iname, chn->chn_ifname) == 0);
	error = cheri_net_data_init(&chn->chn_rx, CHERI_NET_DATABUF_SIZE);
	assert(error == 0 && "no memory");
	error = cheri_net_data_init(&chn->chn_tx, CHERI_NET_DATABUF_SIZE);
	assert(error == 0 && "no memory");

	return 0;
}

/*
 * cheri_net_poll() looks on the file descriptor of tap(4) device in a way which
 * acctype specifies (either read or write) and performs correct type of operation
 * on the file descriptor. After performed operation, data buffer information is
 * updated.
 */
int
cheri_net_poll(cheri_net_t *chnp, int acctype)
{
	struct pollfd  pfd;
	int	e, fd, ret, rxlen, txlen;
	char	*rxbuf;

	assert(chnp != NULL);
	fd = chnp->chn_fd;
	pfd.fd = fd;
	pfd.revents = 0;
	if (acctype == 1) {
		/* Read */
		pfd.events |= POLLIN;
	} else {
		/* Write */
		pfd.events |= POLLOUT;
	}
	e = poll(&pfd, 1, 50);
	assert(e != -1 && "poll() returned an error!");
	if (e != 1) {
		return 0;
	}

	if (pfd.revents & POLLIN) {
		rxbuf = chnp->chn_rx.chnd_data + chnp->chn_rx.chnd_dataidx;
		rxlen = chnp->chn_rx.chnd_datasize - chnp->chn_rx.chnd_dataidx;
		ret = read(fd, rxbuf, rxlen);
		RXDBG("read called; ret=%d, rxlen=%d", ret, rxlen);
		chnp->chn_rx.chnd_dataidx += ret;
		pfd.revents &= ~POLLIN;
		/* XXHACK: update data buffer length */
	} else if (pfd.revents & POLLOUT) {
		txlen = chnp->chn_tx.chnd_dataidx;
		ret = write(fd, chnp->chn_tx.chnd_data, txlen);
		TXDBG("write called; ret=%d, txlen=%d", ret, txlen);
		assert(ret == txlen);
		chnp->chn_tx.chnd_dataidx = 0;
		pfd.revents &= ~POLLOUT;
	}
	return 0;
}

/*
 * Stop CHERI networking.
 */
void
cheri_net_stop(cheri_net_t *chn)
{
	int error;

	assert(chn != NULL);
	assert(chn->chn_fd > 0);
	assert((chn->chn_flags & CHERI_NET_STARTED) != 0);

	error = close(chn->chn_fd);
	assert(error == 0);
}

/*
 * Main handler of CHERI requests. This routine gets called when the access to
 * our memory range happens.
 */
uint32_t
cheri_net_handler(uint32_t addr, uint32_t data, uint32_t acctype)
{
	adapter_t	*app;
	char		*netdevstr;
	uint32_t	 ret;
	int		 error;

	netdevstr = getenv("CHERI_NET_DEV");
	if (netdevstr == NULL) {
		netdevstr = "tap0";
	}

	if (g_cheri_net_inited == 0) {
		error = cheri_net_start(&(g_cheri_net_bsv), netdevstr);
		if (error != 0) {
			fprintf(stderr, "Couldn't start CHERI network: %s "
				"(line %d)\n", strerror(errno), -error);
			abort();
		}
		g_cheri_net_inited = 1;
	}

	app = g_cheri_net_bsv.adpp;
	assert(app != NULL && "app == NULL, but can't");
	ret = app->adp_func(&g_cheri_net_bsv, addr, data, acctype);
	return (ret);
}

/*
 * Initialize adapter's state with required values.
 */
static int
smc_init(cheri_net_t *chnp)
{
	uint32_t	*regfile;
	
	regfile = chnp->adp_regfile;

	regfile[0x50] = 0x115 << 16 | 0;	/* ID_REV = CHIP_9115 */
	regfile[0x64] = 0x87654321;		/* Byte testing register */
	regfile[0x80] = 0x00001200;		/* TX FIFO information */
	regfile[0x8c] = 0x0000ffff;		/* GP timer conf */
	regfile[0x90] = 0x0000ffff;		/* GP timer count, fallthrough */
	regfile[0xff00 + 0x00] = 0x00400000;	/* MAC control register */
	regfile[0xff00 + 0x02] = 0x0000ffff;	/* CSR register ADDRH */
	regfile[0xff00 + 0x03] = 0xffffffff;	/* CSR register ADDRL */

	return 0;
}

static uint32_t
smc_handler(cheri_net_t *chnp, uint32_t addr, uint32_t data, uint32_t acctype)
{
	uint32_t	*regfilep;
	uint32_t	rdata, csr_addr, is_firstseg, is_lastseg;
	int		is_rd, is_tx, is_wr, rx_bytes_used, csr;
	int		tx_bufsize, error;
	static uint32_t	tx_cmd_a, tx_cmd_b;
	static int	which_tx = 0;

	assert(chnp != NULL);
	assert(addr < ARRAY_SIZE(chnp->adp_regfile));
	assert(ARRAY_SIZE(chnp->adp_regfile) >= 0xffff);
#if 0
	CNDBG("addr=%#x, data=%#x, acctype=%#x", addr, data, acctype);
#endif

	/*
	 * CSRs are read through the indexed array of register. This array is
	 * separate from all other registers.  It must have its own index.
	 * Index is passed as a first request to 0xa4 register. Data is
	 * read/written through 0xa8 register. I just map CSR array to global
	 * array for simplicity. I map it to high, unused register offsets.
	 */
	regfilep = chnp->adp_regfile;
	csr_addr = 0;
	if (addr == 0xa8) {	/* CSR data request */
		/* Get CSR index written to 0xa4 in the previous write request */
		csr = regfilep[0xa4] & 0xff;
		/* Convert it to a high, unused register address */
		csr_addr = 0xff00 + csr;
	}
	if (csr_addr != 0) {
		addr = csr_addr;
	}
	rx_bytes_used = cheri_net_data_size(&(chnp->chn_rx));
#if 0
	tx_bytes_used = cheri_net_data_size(&(chnp->chn_tx));
#endif
	rdata = 0;
	is_rd = (acctype == 1);
	if (is_rd) {
		rdata = regfilep[addr];
		/*
		 * For known addresses which require active intervention,
		 * overwrite 'rdata' with a proper value. Taken from 9115.pdf
		 * (SMSC); mostly table on page 72.
		 */
		switch (addr) {
		case 0x00:	/* RX_DATA_FIFO */
			error = cheri_net_poll(chnp, acctype);
			assert(error == 0);
			cheri_net_data_get(&(chnp->chn_rx), &rdata, 4);
			break;
		case 0x40:	/* RX_STATUS_FIFO */
			rdata = rx_bytes_used;
			break;
		case 0x7c:	/* RX_FIFO_INF */
			rdata = (rx_bytes_used / 4) << 16 | rx_bytes_used;	/* ?? */
			break;
		default:
			/* We don't do anything special about other addresses */
			break;
		}
	}

	is_wr = !is_rd;
	if (is_wr) {
		regfilep[addr] = data;
	}

	is_tx = (is_wr && (addr == 0x20));	/* Write to TX_DATA_FIFO */
	which_tx = is_tx ? which_tx + 1 : 0;	/* Count TX accesses */
	/*
	 * SMSC expects 2 32-bit descriptions at the beginning of a
	 * data buffer called "Tx command A" and "Tx command B". U-boot's
	 * driver assumes packets will get written in one data buffer. Thus,
	 * command "A" has first/last segment command set.
	 */
	if (which_tx == 1) {			/* TX A cmd, page 50 */
		tx_cmd_a = data;
		is_firstseg = (data >> 13) & 1;	/* "first segment" */
		is_lastseg = (data >> 12) & 1;	/* "last" segment */
		assert(is_firstseg && is_lastseg);
		TXDBG("TxCmdA: %#08x", tx_cmd_a);
	} else if (which_tx == 2) {
		tx_cmd_b = data;
		assert((tx_cmd_a & 0x7ff) == (tx_cmd_b & 0x7ff) &&
			"tx len should be the same in TX cmd A and TX cmd B");
		TXDBG("TxCmdB: %#08x", tx_cmd_b);
	} else if (which_tx > 2) {
		/* Queue data for transmission. */
		cheri_net_data_put(&(chnp->chn_tx), &data, 4);
	}

	/*
	 * We only have TX buffer size when two commands are there
	 */
	tx_bufsize = -1;
	if ((tx_cmd_a != 0) && (tx_cmd_b != 0)) {
		tx_bufsize = tx_cmd_a & 0x7ff;
	}

	/*
	 * Once we have buffer size, check if it's the last transfer.
	 */
	if ((tx_bufsize != -1) && (which_tx == (2 + (tx_bufsize / 4)))) {
		/* 
		 * Make sure we get correct amount of bytes at correct time. So
		 * in terms of which_tx we must have 2 TX commands + TX buffer
		 * size (in words). For data length, we expect data in the
		 * buffer to be equal TX buffer size
		 */
		TXDBG("cheri_net_data_size=%d, tx_bufsize=%d",
			cheri_net_data_size(&chnp->chn_tx), tx_bufsize);
		assert(cheri_net_data_size(&chnp->chn_tx) == tx_bufsize);

		TXDBG("write should happen here which_tx=%d, tx_bufsize=%d", which_tx, tx_bufsize);
		cheri_net_data_inspect(&(chnp->chn_tx), "TX buffer");
		error = cheri_net_poll(chnp, acctype);
		assert(error == 0);
		/* 
		 * U-boot will ask about TX FIFO 0x80 register at the
		 * next stage in its TX path, but we handle that
		 * already (see above)
		 */
		tx_cmd_a = 0;
		tx_cmd_b = 0;
		which_tx = 0;
	}

	return (rdata);
}

static pism_mod_init_t			ethercap_mod_init;
static pism_dev_interrupt_get_t		ethercap_dev_interrupt_get;
static pism_dev_request_ready_t		ethercap_dev_request_ready;
static pism_dev_request_put_t		ethercap_dev_request_put;
static pism_dev_response_ready_t	ethercap_dev_response_ready;
static pism_dev_response_get_t		ethercap_dev_response_get;
static pism_dev_addr_valid_t		ethercap_dev_addr_valid;

static bool
ethercap_mod_init(pism_module_t *mod)
{

	return (true);
}

static bool
ethercap_dev_interrupt_get(pism_device_t *dev)
{

	return (0);
}

static bool
ethercap_dev_request_ready(pism_device_t *dev, pism_data_t *req)
{

	(void)req;	/* Silence from GCC */
	return (0);
}

static void
ethercap_dev_request_put(pism_device_t *dev, pism_data_t *req)
{

	(void)req;
}

static bool
ethercap_dev_response_ready(pism_device_t *dev)
{

	return (0);
}

static pism_data_t
ethercap_dev_response_get(pism_device_t *dev)
{
	pism_data_t dummy;

	return (dummy);
}

static bool
ethercap_dev_addr_valid(pism_device_t *dev, pism_data_t *req)
{

	(void)req;
	return (0);
}

PISM_MODULE_INFO(ethercap_module) = {
	.pm_name = "ethercap",
	.pm_mod_init = ethercap_mod_init,
	.pm_dev_interrupt_get = ethercap_dev_interrupt_get,
	.pm_dev_request_ready = ethercap_dev_request_ready,
	.pm_dev_request_put = ethercap_dev_request_put,
	.pm_dev_response_ready = ethercap_dev_response_ready,
	.pm_dev_response_get = ethercap_dev_response_get,
	.pm_dev_addr_valid = ethercap_dev_addr_valid,
};

#ifdef	TEST
static volatile int	has_signal = 0;
void
signal_handler(int signo)
{

	(void)signo;
	has_signal = 1;
}

/*
 * How to use this test program. Most common case for write testing:
 *
 * ./test -ddd -N 1000 -w128	Sends 1000 frames of 128 bytes each
 *				Full debugging turned on
 */
static void
usage(const char *pn)
{

	(void)fprintf(stderr,
		"usage:\n"
		"\t%s -b\tcheri_net_data* API regression test\n"
		"\t%s -d\tperform read/write tests and wait for the user\n"
		"\t%s -r\tperform read test (untested yet)\n"
		"\t%s -w <num>\tperform write with <num> of bytes\n"
		"\t%s -a\tsimple adapter initialization test\n"
		"\t%s -aa\tsimple adapter's API test\n",
		pn, pn, pn, pn, pn, pn
	);
	exit(64);
}

int
main(int argc, char **argv)
{
	cheri_net_t	*chnp;
	cheri_net_data_t *txdp;
	int		error, flag_a, flag_d, flag_n, flag_r, flag_w;
	int		flag_N, framenum, i, o, txlen, arg_N;
	uint32_t	c, crc, val;

	chnp = &(g_cheri_net_bsv);
	txdp = &(chnp->chn_tx);
	flag_a = flag_d = flag_n = flag_r = flag_w = 0;
	while ((o = getopt(argc, argv, "adnN:rw:")) != -1) {
		switch (o) {
		case 'a':
			flag_a++;
		case 'd':
			flag_d = 1;
			break;
		case 'n':
			flag_n = 1;
			break;
		case 'N':
			flag_N = 1;
			arg_N = atoi(optarg);
			break;
		case 'r':
			flag_r = 1;
			break;
		case 'w':
			flag_w = 1;
			txlen = atoi(optarg);
			break;
		default:
			usage(argv[0]);
			/* NOT REACHED */
		}
	}

	if ((flag_a + flag_d + flag_n + flag_r + flag_w) == 0) {
		fprintf(stderr, "No flags specified\n");
		usage(argv[0]);
	}

	argc -= optind;
	argv += optind;

	if (flag_d) {
		g_debug_mask = 0;
		if (flag_r) {
			g_debug_mask |= DBG_RX_FLAG;
		}
		if (flag_w) {
			g_debug_mask |= DBG_TX_FLAG;
		}
	}

	if (flag_n) {
		printf("CHERI network data structures regression testing\n");
		/* Initialize the data buffer */
		cheri_net_data_init(txdp, 100);
		/* Verify that no data is present */
		assert(cheri_net_data_size(txdp) == 0);

		/* 
		 * Put and get some data inside the buffer 
		 * and check if the expected data portion size matches
		 */
		val = 10;
		cheri_net_data_put(txdp, &val, 4);
		val = 20;
		cheri_net_data_put(txdp, &val, 4);
		val = 30;
		cheri_net_data_put(txdp, &val, 4);
		assert(cheri_net_data_size(txdp) == 12);
		cheri_net_data_get(txdp, &val, 4);
		cheri_net_data_get(txdp, &val, 4);
		cheri_net_data_get(txdp, &val, 4);
		assert(cheri_net_data_size(txdp) == 0);

		/*
		 * Load some more data
		 */
		for (i = 0; i < 100; i++) {
			c = 'a' + (i % 10);
			error = cheri_net_data_put(txdp, &c, 4);
			assert(error == 0);
			error = cheri_net_data_get(txdp, &val, 4);
			assert(error == 0);
			assert(c == val);
		}
		/* Destroy the buffer */
		cheri_net_data_destroy(txdp);
		return 0;
	}

	/*
	 * Adapter test. Try to behave sort of line U-boot. Stages:
	 * (1) Chip detection
	 * (2) MAC address read-back from EEPROM
	 * (3) ... lots of steps for initialization. Registers are written and
	 *     should just work while returning written values
	 * (4) set MAC address
	 */

	/* Step 1a: Byte test */
	val = NRD(0x64);
	assert(val == 0x87654321);

	/* Step 1b: ID rev */
	val = NRD(0x50);
	assert((val >> 16) == 0x115);

	/*
	 * Step 2: read MAC from EEPROM. We expect to behave as if there was
	 * no EEPROM.
	 */
	NWR(0xa4, 2);	/* CSR register ADDRH index */
	val = NRD(0xa8);
	assert(val == 0x0000ffff);
	NWR(0xa4, 3);	/* CSR register ADDRL index */
	val = NRD(0xa8);
	assert(val == 0xffffffff);

	NWR(0xa4, 2);	/* CSR register ADDRH index */
	NWR(0xa8, 0x0000abcd);
	val = NRD(0xa8);
	assert(val == 0x0000abcd);

	NWR(0xa4, 3);	/* CSR register ADDRL index */
	NWR(0xa8, 0xababcdcd);
	val = NRD(0xa8);
	assert(val == 0xababcdcd);

	/* Just an adapter initialization test */
	if (flag_a == 1) {
		return 0;
	}

	/*
	 * Test the data buffer handling (flow). So basically how many bytes
	 * buffer claims to have after data has been written and what kind
	 * of data is in the buffer (its contents)
	 */
	if (flag_a == 2) {
		/* TxCmdA == 123 in lenght + bits 12 and 13 set */
		NWR(0x20, 123 | (0x3 << 12));
		/* TxCmdB has the same length */
		NWR(0x20, 123);
		/* Some random data */
		NWR(0x20, 0x11223344);
		NWR(0x20, 0xaabb);
		cheri_net_data_inspect(txdp, "Tx buffer testing");
		assert(cheri_net_data_size(txdp) == 8);
		return 0;
	}

	if (flag_w) {
		for (framenum = 0; framenum < arg_N; framenum++) {
			TXDBG("Sending %dth write request txlen=%d", framenum,
				txlen);
			/* TX command A */
			val = (1<<12) | (1<<13) | txlen;
			NWR(0x20, val);

			/* TX command B */
			val = txlen;
			NWR(0x20, val);

			NWR(0x20, 0x99112233);	/* Src MAC */
			NWR(0x20, 0x4455aabb);

			NWR(0x20, 0xccddabcd);	/* Dest MAC */

			NWR(0x20, 0xffff0008);	/* Network type==h0800 (IP) */

			i = txlen - (4*4);
			i -= 4;			/* Leave a space for CRC */
			while (i) {
				NWR(0x20, 0x55555555);
				i -= 4;
			}
			crc = cheri_net_data_crc(txdp);
			NWR(0x20, crc);	/* CRC is last and should trigger write */
			assert(cheri_net_data_size(txdp) == 0);
			sleep(1);
		}
	}

	if (flag_d + flag_r > 0) {
		signal(SIGINT, signal_handler);
		for (;;) {
			if (flag_r) {
				val = NRD(0x00);
				RXDBG("Read %08x", val);
			}
			if (has_signal) {
				printf("Got a signal - exiting.\n");
				break;
			}
		}
	}
	return (0);
}
#endif
