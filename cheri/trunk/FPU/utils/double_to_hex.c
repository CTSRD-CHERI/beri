/*-
 * Copyright (c) 2013 Colin Rothwell
 * All rights reserved.
 *
 * This software was developed by Colin Rothwell as part of his final year
 * undergraduate project.
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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    unsigned int first;
    unsigned int second;
} UIntPair;

typedef union {
    double d;
    UIntPair uip;
} UIntAndDouble;

int main(int argc, char* argv[]) {
    if (argc != 2) {
        printf("Usage: double_to_hex <floating point value>\n");
        return 1;
    }

    char* end;
    UIntAndDouble in;
    in.d = strtod(argv[1], &end);
    if (end != argv[1] + strlen(argv[1])) {
        printf("Not a valid floating point value.\n");
        return 2;
    }

    printf("%08X%08X", in.uip.second, in.uip.first);
    return 0;
}
