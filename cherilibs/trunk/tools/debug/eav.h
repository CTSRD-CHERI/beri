/*-
 * Copyright (c) 2013 SRI International
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

#ifndef __EAV_H__
#define __EAV_H__

enum eav_error {
	EAV_SUCCESS = 0,
	EAV_ERR_MEM,
	EAV_ERR_DIGEST,
	EAV_ERR_DIGEST_UNKNOWN,
	EAV_ERR_DIGEST_UNSUPPORTED,
	EAV_ERR_COMP,
	EAV_ERR_COMP_UNKNOWN,
	EAV_ERR_COMP_UNSUPPORTED
};

enum eav_digest {
	EAV_DIGEST_NONE = 0,
	EAV_DIGEST_MD5
};

enum eav_compression {
	EAV_COMP_NONE = 0,
	EAV_COMP_BZIP2,
	EAV_COMP_GZIP,
	EAV_COMP_XZ,

	EAV_COMP_UNKNOWN
};

enum eav_compression eav_taste(const unsigned char *buf, off_t len);
const char *eav_strerror(enum eav_error error);
enum eav_error extract_and_verify(unsigned char *ibuf, size_t ilen,
    unsigned char **obufp, size_t *olenp, size_t blocksize,
    enum eav_compression ctype,
    enum eav_digest dtype, const unsigned char *digest);

#endif /* __EAV_H__ */
