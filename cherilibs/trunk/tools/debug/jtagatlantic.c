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

#include <stdlib.h>
#include <stdio.h>
#include <assert.h>
#include "jtagatlantic.h"


typedef struct {
	int		error_code;
	const char *	error_string;
} atlantic_error_mapping_t;

static const atlantic_error_mapping_t atlantic_errors[] = {
	{ -1, "Unable to connect to local JTAG server" },
	{ -2, "More than one cable available, provide a more specific cable name" },
	{ -3, "Cable not available" },
	{ -4, "Selected cable is not attached" },
	{ -5, "JTAG not connected to board, or board powered down" },
	{ -6, "Program \"%s\" is already using the JTAG UART" },
	{ -7, "More than one UART available, specify device/instance" },
	{ -8, "No UART matching the specified device/instance" },
	{ -9, "Selected UART is not compatible with this version of libjtag_atlantic.so library" },
	{  0, "Unknown JTAG Atlantic error" }
};


/* The libjtag_atlantic.so library only has C++ library bindings, not C.
 * To avoid having to build everything as C++, we simply provide un-mangled wrapper functions
 */

extern JTAGATLANTIC * _Z17jtagatlantic_openPKciiS0_(const char * chain, int device_index, int link_instance, const char * app_name);
extern int _Z22jtagatlantic_get_errorPPKc(const char * * other_info);
extern void _Z18jtagatlantic_closeP12JTAGATLANTIC(JTAGATLANTIC * link);
extern int _Z18jtagatlantic_writeP12JTAGATLANTICPKcj(JTAGATLANTIC * link, const char * data, unsigned int count);
extern int _Z18jtagatlantic_flushP12JTAGATLANTIC(JTAGATLANTIC * link);
extern int _Z17jtagatlantic_readP12JTAGATLANTICPcj(JTAGATLANTIC * link, char * buffer, unsigned int buffsize);
extern int _Z22jtagatlantic_wait_openP12JTAGATLANTIC(JTAGATLANTIC*);
extern void _Z21jtagatlantic_get_infoP12JTAGATLANTICPPKcPiS4_(JTAGATLANTIC*, char const**, int*, int*);
extern int _Z26jtagatlantic_cable_warningP12JTAGATLANTIC(JTAGATLANTIC*);
extern int _Z26jtagatlantic_is_setup_doneP12JTAGATLANTIC(JTAGATLANTIC*);
extern int _Z28jtagatlantic_bytes_availableP12JTAGATLANTIC(JTAGATLANTIC*);


JTAGATLANTIC * jtagatlantic_open(const char * chain, int device_index, int link_instance, const char * app_name)
{
	return _Z17jtagatlantic_openPKciiS0_(chain, device_index, link_instance, app_name);
}

int jtagatlantic_get_error(const char * * other_info)
{
	return _Z22jtagatlantic_get_errorPPKc(other_info);
}

void jtagatlantic_close(JTAGATLANTIC * link)
{
	_Z18jtagatlantic_closeP12JTAGATLANTIC(link);
}

int jtagatlantic_write(JTAGATLANTIC * link, const char * data, unsigned int count)
{
	return _Z18jtagatlantic_writeP12JTAGATLANTICPKcj(link, data, count);
}

int jtagatlantic_flush(JTAGATLANTIC * link)
{
	return _Z18jtagatlantic_flushP12JTAGATLANTIC(link);
}

int jtagatlantic_read(JTAGATLANTIC * link, char * buffer, unsigned int buffsize)
{
	return _Z17jtagatlantic_readP12JTAGATLANTICPcj(link, buffer, buffsize);
}

int jtagatlantic_is_setup_done(JTAGATLANTIC * link)
{
	return _Z26jtagatlantic_is_setup_doneP12JTAGATLANTIC(link);
}

int jtagatlantic_wait_open(JTAGATLANTIC *link)
{
	return _Z22jtagatlantic_wait_openP12JTAGATLANTIC(link);
}

int jtagatlantic_bytes_available(JTAGATLANTIC *link)
{
	return _Z28jtagatlantic_bytes_availableP12JTAGATLANTIC(link);
}

void jtagatlantic_get_info(JTAGATLANTIC *link, char const **cable, int *device, int *instance)
{
	return _Z21jtagatlantic_get_infoP12JTAGATLANTICPPKcPiS4_(link, cable, device, instance);
}

int jtagatlantic_cable_warning(JTAGATLANTIC *link)
{
	return _Z26jtagatlantic_cable_warningP12JTAGATLANTIC(link);
}
      

/*
 * beri_jtagatlantic_geterror
 * 
 * Ask the JTAG Atlantic library what its error status is, converting it into an error string
 * that is returned in a caller-supplied buffer.
 * Parameters:
 * char *error_string: pointer to string buffer that will be filled in
 * int error_string_len: length of string buffer that can be filled in
 * Returns:
 * char *: pointer to error_string
 */


char *beri_jtagatlantic_geterror(char *error_string, int error_string_len)
{
	const char *	jtagerror_progname;
	int	jtagerror_num;
	int	i = 0, error_code = 0;

	assert(error_string != NULL);

	/* Ask the JTAG Atlantic library what error we had (and what program if any clashed with us) */
	jtagerror_num = jtagatlantic_get_error(&jtagerror_progname);

	printf("jtagerror_progname = %s\n", jtagerror_progname);
	
	/* Scan through the table of error messages looking for the appropriate index */
	i = 0;
	do 
	{
		error_code = atlantic_errors[i].error_code;
		if (jtagerror_num == error_code)
			break;
		i++;
	} while (error_code);
	
	/* We found should have found an error message, in the worst case 'Unknown error' */
	assert(atlantic_errors[i].error_string != NULL);

	/* Copy the message into our caller's buffer, substituting in the program name supplied (if any) */
	snprintf(error_string, error_string_len, atlantic_errors[i].error_string, jtagerror_progname);

	return error_string;
}


