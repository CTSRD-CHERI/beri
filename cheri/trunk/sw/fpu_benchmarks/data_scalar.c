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


#include "write.h"
#include "std.h"
#include "mipsmath.h"

#define ALLOC_DATA_ARRAY cheriMalloc(DATA_COUNT * sizeof(float));

typedef union {
    uint u;
    float f;
} UIntFloat;

static void generateData(float* data) {
    UIntFloat datum;
    uint i;
    for (i = 0; i < DATA_COUNT; ++i) {
        datum.u = cheriRand();
        data[i] = datum.f;
    }
}

#define CREATE_MAP_MONAD(op) \
    static void map_ ## op(float* input, float* output) { \
        uint i; \
        for (i = 0; i < DATA_COUNT; ++i) { \
            output[i] = op(input[i]); \
        } \
    }

#define CREATE_MAP_DIAD(op) \
    static void map_ ## op(float* left, float* right, float* output) { \
        uint i; \
        for (i = 0; i < DATA_COUNT; ++i) { \
            output[i] = op(left[i], right[i]); \
        } \
    }

static inline float add(float left, float right) { return left + right; }
CREATE_MAP_DIAD(add);
static inline float mul(float left, float right) { return left * right; }
CREATE_MAP_DIAD(mul);
static inline float sub(float left, float right) { return left - right; }
CREATE_MAP_DIAD(sub);
static inline float div(float left, float right) { return left / right; }
CREATE_MAP_DIAD(div);
static inline float neg(float input) { return -input; }
CREATE_MAP_MONAD(neg);
CREATE_MAP_MONAD(absf);
CREATE_MAP_MONAD(sqrtf);
CREATE_MAP_MONAD(rsqrtf);
CREATE_MAP_MONAD(recipf);

void runDataTestsScalar() {
    float* left = ALLOC_DATA_ARRAY;
    generateData(left);
    float* right = ALLOC_DATA_ARRAY;
    generateData(right);
    float* result = ALLOC_DATA_ARRAY;

    TimeUnit start = startTiming();

    map_add(left, right, result);
    map_absf(left, result);
    map_sub(left, right, result);
    map_div(left, right, result);
    map_neg(left, result);
    map_mul(left, right, result);
    map_sqrtf(left, result);
    map_rsqrtf(left, result);
    map_recipf(left, result);

    finishTiming(start);
}
