/*-
 * Copyright (c) 2000-2011 Dag-Erling Smørgrav
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer
 *    in this position and unchanged.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. The name of the author may not be used to endorse or promote products
 *    derived from this software without specific prior written permission
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 * IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 * INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 * NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#include <sys/time.h>

#include <stdio.h>
#include <inttypes.h>
#include <unistd.h>

#include "status_bar.h"

int v_tty = 1;
int v_level = 1;

/*
 * Compute and display ETA
 */
static const char *
stat_eta(struct xferstat *xs)
{
	static char str[16];
	long elapsed, eta;
	off_t received, expected;

	elapsed = xs->last.tv_sec - xs->start.tv_sec;
	received = xs->rcvd - xs->offset;
	expected = xs->size - xs->rcvd;
	eta = (long)((double)elapsed * expected / received);
	if (eta > 3600)
		snprintf(str, sizeof str, "%02ldh%02ldm",
		    eta / 3600, (eta % 3600) / 60);
	else
		snprintf(str, sizeof str, "%02ldm%02lds",
		    eta / 60, eta % 60);
	return (str);
}

/*
 * Format a number as "xxxx YB" where Y is ' ', 'k', 'M'...
 */
static const char *prefixes = " kMGTP";
static const char *
stat_bytes(off_t bytes)
{
	static char str[16];
	const char *prefix = prefixes;

	while (bytes > 9999 && prefix[1] != '\0') {
		bytes /= 1024;
		prefix++;
	}
	snprintf(str, sizeof str, "%4jd %cB", (intmax_t)bytes, *prefix);
	return (str);
}

/*
 * Compute and display transfer rate
 */
static const char *
stat_bps(struct xferstat *xs)
{
	static char str[16];
	double delta, bps;

	delta = (xs->last.tv_sec + (xs->last.tv_usec / 1.e6))
	    - (xs->start.tv_sec + (xs->start.tv_usec / 1.e6));
	if (delta == 0.0) {
		snprintf(str, sizeof str, "?? Bps");
	} else {
		bps = (xs->rcvd - xs->offset) / delta;
		snprintf(str, sizeof str, "%sps", stat_bytes((off_t)bps));
	}
	return (str);
}

/*
 * Update the stats display
 */
static void
stat_display(struct xferstat *xs, int force)
{
	struct timeval now;

	gettimeofday(&now, NULL);
	if (!force && now.tv_sec <= xs->last.tv_sec)
		return;
	xs->last = now;

	fprintf(stderr, "\r%-46.46s", xs->name);
	if (xs->size <= 0) {
#ifdef HAVE_SETPROCTITLE
		setproctitle("%s [%s]", xs->name, stat_bytes(xs->rcvd));
#endif
		fprintf(stderr, "        %s", stat_bytes(xs->rcvd));
	} else {
#ifdef HAVE_SETPROCTITLE
		setproctitle("%s [%d%% of %s]", xs->name,
		    (int)((100.0 * xs->rcvd) / xs->size),
		    stat_bytes(xs->size));
#endif
		fprintf(stderr, "%3d%% of %s",
		    (int)((100.0 * xs->rcvd) / xs->size),
		    stat_bytes(xs->size));
	}
	fprintf(stderr, " %s", stat_bps(xs));
	if (xs->size > 0 && xs->rcvd > 0 &&
	    xs->last.tv_sec >= xs->start.tv_sec + 10)
		fprintf(stderr, " %s", stat_eta(xs));
}

/*
 * Initialize the transfer statistics
 */
void
stat_start(struct xferstat *xs, const char *name, off_t size, off_t offset)
{
	snprintf(xs->name, sizeof xs->name, "%s", name);
	gettimeofday(&xs->start, NULL);
	xs->last.tv_sec = xs->last.tv_usec = 0;
	xs->size = size;
	xs->offset = offset;
	xs->rcvd = offset;
	if (v_tty && v_level > 0)
		stat_display(xs, 1);
	else if (v_level > 0)
		fprintf(stderr, "%-46s", xs->name);
}

/*
 * Update the transfer statistics
 */
void
stat_update(struct xferstat *xs, off_t rcvd)
{
	xs->rcvd = rcvd;
	if (v_tty && v_level > 0)
		stat_display(xs, 0);
}

/*
 * Finalize the transfer statistics
 */
void
stat_end(struct xferstat *xs)
{
	gettimeofday(&xs->last, NULL);
	if (v_tty && v_level > 0) {
		stat_display(xs, 1);
		putc('\n', stderr);
	} else if (v_level > 0) {
		fprintf(stderr, "        %s %s\n",
		    stat_bytes(xs->size), stat_bps(xs));
	}
}
