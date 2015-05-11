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

#define VECTORISE_MONADIC_OP(op) \
    static inline v4sf vector_ ## op(v4sf input) { \
        v4sf out; \
        out[0] = op(input[0]); \
        out[1] = op(input[1]); \
        out[2] = op(input[2]); \
        out[3] = op(input[3]); \
        return out; \
    }

#define CREATE_MAP_MONAD(op) \
    void map_ ## op(float* restrict input, float* restrict output) { \
        v4sf* inputData; \
        v4sf* outputData; \
        uint i; \
        for (i = 0; i < DATA_COUNT; i += 4) { \
            inputData = (v4sf*)(input + 4); \
            outputData = (v4sf*)(output + 4); \
            *outputData = op(*inputData); \
        } \
    }

#define CREATE_MAP_DIAD(op) \
    void map_ ## op(float* restrict left, float* restrict right, float* restrict output) { \
        v4sf* leftData; \
        v4sf* rightData; \
        v4sf* outputData; \
        uint i; \
        for (i = 0; i < DATA_COUNT; i += 4) { \
            leftData = (v4sf*)(left + i); \
            rightData = (v4sf*)(right + i); \
            outputData = (v4sf*)(output + i); \
            *outputData = op(*leftData, *rightData); \
        } \
    }

static inline v4sf add(v4sf left, v4sf right) { return left + right; }
CREATE_MAP_DIAD(add);

static inline v4sf mul(v4sf left, v4sf right) { return left * right; }
CREATE_MAP_DIAD(mul);

static inline v4sf sub(v4sf left, v4sf right) { return left - right; }
CREATE_MAP_DIAD(sub);

static inline v4sf div(v4sf left, v4sf right) { return left / right; }
CREATE_MAP_DIAD(div);

static inline v4sf neg(v4sf input) { return -input; }
CREATE_MAP_MONAD(neg);

VECTORISE_MONADIC_OP(absf);
CREATE_MAP_MONAD(vector_absf);

VECTORISE_MONADIC_OP(sqrtf);
CREATE_MAP_MONAD(vector_sqrtf);

VECTORISE_MONADIC_OP(rsqrtf);
CREATE_MAP_MONAD(vector_rsqrtf);

VECTORISE_MONADIC_OP(recipf);
CREATE_MAP_MONAD(vector_recipf);

void runDataTestsVectorised() {
    float* left = ALLOC_DATA_ARRAY;
    generateData(left);
    float* right = ALLOC_DATA_ARRAY;
    generateData(right);
    float* result = ALLOC_DATA_ARRAY;

    TimeUnit start = startTiming();

    map_add(left, right, result);
    map_vector_absf(left, result);
    map_sub(left, right, result);
    map_div(left, right, result);
    map_neg(left, result);
    map_mul(left, right, result);
    map_vector_sqrtf(left, result);
    map_vector_rsqrtf(left, result);
    map_vector_recipf(left, result);

    finishTiming(start);
}
