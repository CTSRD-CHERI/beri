/*
 * Copyright (c) 2015 Theo Markettos
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

/* Definitions for the libjtag_atlantic shared library provided by Altera
 */

typedef struct JTAGATLANTIC JTAGATLANTIC;

JTAGATLANTIC * jtagatlantic_open(const char * chain, int device_index, int link_instance, const char * app_name);
int jtagatlantic_get_error(const char * * other_info);
void jtagatlantic_close(JTAGATLANTIC * link);
int jtagatlantic_write(JTAGATLANTIC * link, const char * data, unsigned int count);
int jtagatlantic_flush(JTAGATLANTIC * link);
int jtagatlantic_read(JTAGATLANTIC * link, char * buffer, unsigned int buffsize);
int jtagatlantic_is_setup_done(JTAGATLANTIC * link);
int jtagatlantic_wait_open(JTAGATLANTIC *link);
int jtagatlantic_bytes_available(JTAGATLANTIC *link);
void jtagatlantic_get_info(JTAGATLANTIC *link, char const **cable, int *device, int *instance);
int jtagatlantic_cable_warning(JTAGATLANTIC *link);


char *beri_jtagatlantic_geterror(char *error_string, int error_string_len);

