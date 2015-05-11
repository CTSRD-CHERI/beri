/*-
 * Copyright (c) 2011-2012 Philip Paeps
 * Copyright (c) 2011-2012 Robert N. M. Watson
 * Copyright (c) 2011 Jonathan Woodruff
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

#include <sys/types.h>
#include <sys/mman.h>
#include <sys/queue.h>

#include <assert.h>
#if defined(__linux__)
#include <endian.h>
#elif defined(__FreeBSD__)
#include <sys/endian.h>
#endif
#include <err.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>
#include <stdbool.h>
#include <unistd.h>

#include <SDL/SDL.h>

#include "pismdev/pism.h"
#include "include/parameters.h"

/*
 * Combined driver for the tPad touch screen frame buffer and touch input.
 */

static pism_dev_request_ready_t		fb_dev_request_ready;
static pism_dev_request_put_t		fb_dev_request_put;
static pism_dev_response_ready_t	fb_dev_response_ready;
static pism_dev_response_get_t		fb_dev_response_get;
static pism_dev_addr_valid_t		fb_dev_addr_valid;

pism_data_t	fb_fifo;	//	1-element FIFO for requests
int		fb_fifo_empty = 1;
bool interrupt;
static SDL_Surface *screen;

/*
 * Basic frame buffer parameters.
 */
#define	FRAMEBUFFER_WIDTH	800
#define	FRAMEBUFFER_HEIGHT	600

/*
 * We trigger an SDL update at least frequent intervals than memory writes in
 * order to avoid high refresh costs.  To this end, remember what bits of the
 * screen have been written.
 */
static uint64_t	cycle_last_tick;
static uint64_t	cycle_last_update;
static u_int	x_lower = -1, x_upper = -1;
static u_int	y_lower = -1, y_upper = -1;

#define	UPDATE_RATE	50000

static char	*g_fb_debug = NULL;
#define	UDBG(...)	do	{		\
	if (g_fb_debug == NULL) {		\
		break;				\
	}					\
	printf("%s(%d): ", __func__, __LINE__);	\
	printf(__VA_ARGS__);			\
	printf("\n");				\
} while (0)

#define	FRAMEBUFFER_BASE	(CHERI_FRAMEBUF_BASE)
#define	FRAMEBUFFER_LENGTH	(FRAMEBUFFER_WIDTH * FRAMEBUFFER_HEIGHT * 2)
#define	TOUCHSCREEN_BASE	(CHERI_TOUCHSCREEN_BASE)
#define	TOUCHSCREEN_LENGTH	(3 * sizeof(uint32_t))

/*
 * XXXRW: This frame buffer simulation may have non-trivial word/byte order
 * problems.  However, it currently appears to work on 64-bit Intel systems.
 */
#define	FRAMEBUFFER_REDSHIFT	3	/* 5-bit colour into 8-bit colour. */
#define	FRAMEBUFFER_GREENSHIFT	2	/* 6-bit colour into 8-bit colour. */
#define	FRAMEBUFFER_BLUESHIFT	3	/* 5-bit colour into 8-bit colour. */

/*
 * Register offsets for touch input.
 */
#define	TOUCHSCREEN_X_OFFSET		0
#define	TOUCHSCREEN_Y_OFFSET		sizeof(uint32_t)
#define	TOUCHSCREEN_DOWN_OFFSET		(2 * sizeof(uint32_t))

#define	FRAMEBUFFER_OPTION_LAZY	"lazy"

static int fb_counter;			/* Number of FB devices. */
static bool fb_initialised;		/* Initialise on first use. */

static void
putpixel(SDL_Surface *surface, int x, int y, uint32_t pixel)
{
	int bpp = surface->format->BytesPerPixel;
	void *p;

	p = surface->pixels + y * surface->pitch + x * bpp;
	switch (bpp) {
	case 1:
		*((uint8_t *)p) = pixel;
		break;

	case 2:
		*((uint16_t *)p) = pixel;
		break;

	case 4:
		*((uint32_t *)p) = pixel;
		break;
	}
}

static bool
fb_mod_init(pism_module_t *mod)
{

	g_fb_debug = getenv("CHERI_DEBUG_FB");
	return (true);
}

static bool
fb_dev_init_internal(pism_device_t *dev)
{

	if (fb_initialised)
		return (true);
	fb_initialised = true;
	SDL_Init(SDL_INIT_VIDEO);
	screen = SDL_SetVideoMode(FRAMEBUFFER_WIDTH, FRAMEBUFFER_HEIGHT, 16,
	    SDL_SWSURFACE);
	if (screen == NULL) {
		fprintf(stderr, "Couldn't get screen: %s\n", SDL_GetError());
		return (false);
	}
	return (true);
}

static bool
fb_dev_init(pism_device_t *dev)
{
	const char *optval;
	bool lazy;

	if (fb_counter != 0) {
		warnx("%s: too many frame buffers configured", __func__);
		return (false);
	}
	fb_counter++;

	if (pism_device_option_get(dev, FRAMEBUFFER_OPTION_LAZY, &optval)) {
		if (!(pism_device_option_parse_bool(dev, optval, &lazy))) {
			warnx("%s: invalid lazy option on device %s",
			    __func__, dev->pd_name);
			return (false);
		}
	} else
		lazy = false;
	if (!lazy) {
		if (!(fb_dev_init_internal(dev)))
			return (false);
	}
	return (true);
}

static bool
fb_dev_request_ready(pism_device_t *dev, pism_data_t *req)
{

	if (fb_fifo_empty)
		return (1);
	return (0);
}

/*
 * Return whether or not the write mask for a byte of data in the
 * pism_data_int is set.
 */
static __inline int
pd_byteenable_isbitset(struct pism_data_int *pd_int, int i)
{

	if (pd_int->pdi_byteenable & (1 << i))
		return (1);
	return (0);
}

/*
 * Convert an address and offset into a global pixel number, which can be
 * further chewed into coordinates.
 */
static __inline u_int
pd_addr_top(struct pism_data_int *pd_int, int i)
{

	return ((pd_int->pdi_addr + i - FRAMEBUFFER_BASE) / sizeof(uint16_t));

}

/*
 * Convert an address and offset into an X coordinate.
 */
static __inline u_int
pd_addr_tox(struct pism_data_int *pd_int, int i)
{

	/* XXXRW: Potential byte/bit order issue here. */
	/* XXXRW: No bounds checking. */
	return (pd_addr_top(pd_int, i) % FRAMEBUFFER_WIDTH);
}

/*
 * Convert an address and offset into a Y coordinate.
 */
static __inline u_int
pd_addr_toy(struct pism_data_int *pd_int, int i)
{

	/* XXXRW: Potential byte/bit order issue here. */
	/* XXXRW: No bounds checking. */
	return (pd_addr_top(pd_int, i) / FRAMEBUFFER_WIDTH);
}

/*
 * Convert a short of data from the I/O into an SDL colour.
 */
static __inline uint32_t
pd_data_tocolor(uint16_t d)
{

	return (SDL_MapRGB(screen->format, (d >> 11) << FRAMEBUFFER_REDSHIFT,
	    ((d >> 5) & 0x3f) << FRAMEBUFFER_GREENSHIFT,
	    (d & 0x1f) << FRAMEBUFFER_BLUESHIFT));
}

static void
framebuffer_request_put(struct pism_data_int *pd_int)
{
	uint32_t c;
	uint16_t data;
	int i, x, y;

#if 0
	switch (pd_int->pdi_acctype) {
	case PISM_ACC_FETCH:
		/* Allow frame buffer reads to fall through to DRAM. */
		return;

	case PISM_ACC_STORE:
		break;

	default:
		printf("framebuffer: unrecognised acctype %d",
		    pd_int->pdi_acctype);
		return;
	}
#endif

	/*
	 * XXXRW: For now, require that writes come in in multiples of 16 bits
	 * -- this will break memcpy() to the frame buffer, but makes coding
	 * here easier.  Otherwise, we'd need to intuit the remaining bytes
	 * from a 16-bit pixel from screen data or a local buffer in memory.
	 */
	for (i = 0; i < PISM_DATA_BYTES; i += 2) {
		if (!pd_byteenable_isbitset(pd_int, i))
			continue;
		if (!pd_byteenable_isbitset(pd_int, i + 1))
			continue;

		/*
		 * Pixel data arrive as 16-bit, little-endian; arrange in
		 * native byte order, whatever that may be.
		 */
		data = pd_int->pdi_data[i];
		data |= pd_int->pdi_data[i + 1] << 8;

		x = pd_addr_tox(pd_int, i);
		y = pd_addr_toy(pd_int, i);
		c = pd_data_tocolor(data);

		if (SDL_MUSTLOCK(screen)) {
			if (SDL_LockSurface(screen) < 0)
				return;
		}
		putpixel(screen, x, y, c);
		if (SDL_MUSTLOCK(screen))
			SDL_UnlockSurface(screen);
	}

	/*
	 * Conservatively update the entire block of pixels.  Not clear if
	 * this hurts us or not.
	 */
	if (x_lower == -1) {
		x_lower = pd_addr_tox(pd_int, 0);
		x_upper = pd_addr_tox(pd_int, 31);
		y_lower = pd_addr_toy(pd_int, 0);
		y_upper = y_lower;
	} else {
		u_int tmp;

		tmp = pd_addr_tox(pd_int, 0);
		if (tmp < x_lower)
			x_lower = tmp;
		tmp = pd_addr_tox(pd_int, PISM_DATA_BYTES - 1);
		if (tmp > x_upper)
			x_upper = tmp;
		tmp = pd_addr_toy(pd_int, 0);
		if (tmp < y_lower)
			y_lower = tmp;
		if (tmp > y_upper)
			y_upper = tmp;
	}
}

static void
touchscreen_request_enqueue(pism_data_t *req)
{

	/* Input requires us to respond later, so enqueue. */
	memcpy(&fb_fifo, req, sizeof(fb_fifo));
	fb_fifo_empty = 0;
}

static void
fb_dev_request_put(pism_device_t *dev, pism_data_t *req)
{
	struct pism_data_int *pd_int;

	(void)fb_dev_init_internal(dev);
	pd_int = &req->pd_int;
	if (pd_int->pdi_addr >= FRAMEBUFFER_BASE &&
	    pd_int->pdi_addr < FRAMEBUFFER_BASE + FRAMEBUFFER_LENGTH)
		framebuffer_request_put(pd_int);
	if (pd_int->pdi_addr >= TOUCHSCREEN_BASE &&
	    pd_int->pdi_addr < TOUCHSCREEN_BASE + TOUCHSCREEN_LENGTH)
		touchscreen_request_enqueue(req);
}

static bool
fb_dev_response_ready(pism_device_t *dev)
{

	if (!fb_fifo_empty)
		return (1);
	return (0);
}

static void
framebuffer_response_get(struct pism_data_int *pd_int)
{

	/* XXXRW: nothing here currently. */
}

static void
touchscreen_response_get(struct pism_data_int *pd_int)
{
	int32_t *datap;
	int x, y, down;

#if 0
	switch (pd_int->pdi_acctype) {
	case PISM_ACC_FETCH:
		break;

	case PISM_ACC_STORE:
		/* Ignore writes. */
		return;

	default:
		printf("touchscreen: unrecognised acctype %d",
		    pd_int->pdi_acctype);
		return;
	}
#endif

	// -= TOUCHSCREEN_BASE;

	SDL_PumpEvents();
	down = SDL_GetMouseState(&x, &y);

	/*
	 * Touch screen memory values are little endian.
	 */
	datap = (int32_t *)&pd_int->pdi_data[TOUCHSCREEN_DOWN_OFFSET];
	*datap = htole32(down);

	datap = (int32_t *)&pd_int->pdi_data[TOUCHSCREEN_X_OFFSET];
	*datap = htole32(x);

	datap = (int32_t *)&pd_int->pdi_data[TOUCHSCREEN_Y_OFFSET];
	*datap = htole32(y);
}

static pism_data_t
fb_dev_response_get(pism_device_t *dev)
{
	struct pism_data_int *pd_int;

	(void)fb_dev_init_internal(dev);
	pd_int = &fb_fifo.pd_int;
	if (pd_int->pdi_addr >= FRAMEBUFFER_BASE &&
	    pd_int->pdi_addr < FRAMEBUFFER_BASE + FRAMEBUFFER_LENGTH)
		framebuffer_response_get(pd_int);
	if (pd_int->pdi_addr >= TOUCHSCREEN_BASE &&
	    pd_int->pdi_addr < TOUCHSCREEN_BASE + TOUCHSCREEN_LENGTH)
		touchscreen_response_get(pd_int);
	fb_fifo_empty = 0;
	return (fb_fifo);
}

static bool
fb_dev_addr_valid(pism_device_t *dev, pism_data_t *req)
{
	struct pism_data_int *pd_int;

	pd_int = &req->pd_int;
	if (pd_int->pdi_addr >= FRAMEBUFFER_BASE &&
	    pd_int->pdi_addr < FRAMEBUFFER_BASE + FRAMEBUFFER_LENGTH)
		return (1);
	if (pd_int->pdi_addr >= TOUCHSCREEN_BASE &&
	    pd_int->pdi_addr < TOUCHSCREEN_BASE + TOUCHSCREEN_LENGTH)
		return (1);
	return (0);
}

static void
fb_dev_cycle_tick(pism_device_t *dev)
{

	if (!fb_initialised)
		return;

	cycle_last_tick++;
	if (cycle_last_tick < cycle_last_update + UPDATE_RATE)
		return;
	if (x_lower == -1)
		return;
	SDL_UpdateRect(screen, x_lower, y_lower, x_upper - x_lower + 1,
	    y_upper - y_lower + 1);
	x_lower = x_upper = -1;
	y_lower = y_upper = -1;
	cycle_last_update = cycle_last_tick;
}

static const char *framebuffer_option_list[] = {
	FRAMEBUFFER_OPTION_LAZY,
	NULL
};

PISM_MODULE_INFO(fb_module) = {
	.pm_name = "framebuffer",
	.pm_option_list = framebuffer_option_list,
	.pm_mod_init = fb_mod_init,
	.pm_dev_init = fb_dev_init,
	.pm_dev_request_ready = fb_dev_request_ready,
	.pm_dev_request_put = fb_dev_request_put,
	.pm_dev_response_ready = fb_dev_response_ready,
	.pm_dev_response_get = fb_dev_response_get,
	.pm_dev_addr_valid = fb_dev_addr_valid,
	.pm_dev_cycle_tick = fb_dev_cycle_tick,
};
