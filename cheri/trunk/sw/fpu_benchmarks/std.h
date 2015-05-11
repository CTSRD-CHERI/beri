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

#ifndef STD_H
#define STD_H

#ifndef MIPS
#include <time.h>
#endif

typedef unsigned char byte;
typedef unsigned int uint;
typedef unsigned long ulong;

typedef float v4sf __attribute__ ((vector_size (16)));

static inline v4sf newV4sf(float x, float y, float z, float w) {
    return (v4sf){x, y, z, w};
}

static inline v4sf replicateToV4sf(float x) {
    return newV4sf(x, x, x, x);
}

static inline float getV4sfElement(v4sf vec, uint element) {
    return vec[element];
}

extern const uint IMG_WIDTH;
extern const uint IMG_HEIGHT;
extern const uint IMG_ARRAY_LENGTH;

extern const uint DATA_COUNT;

extern const uint MAX_ITERATIONS;
extern const float CEN_X;
extern const float CEN_Y;
extern const float SCALE;

extern const float SPHERE_STEP; 
extern const float PLANE_STEP;

void* cheriMalloc(uint size);

#ifdef MIPS
typedef uint TimeUnit;
#else
typedef struct timespec TimeUnit;
#endif

TimeUnit startTiming();
void finishTiming(TimeUnit startTime);

void setPixel(byte* img, int x, int y, byte r, byte g, byte b);

void outputImage(char* name, const byte* img);

uint cheriRand();

#endif
