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
#include "mipsmath.h"

const float PI = 3.1415927f;

// From "http://devmaster.net/forums/topic/4648-fast-and-accurate-sinecosine/"
float cheriSinf(float x) {
    const float B = 4.f/PI;
    const float C = -4.f/(PI*PI);
    const float P = 0.225f;

    float y = B * x + C * x * absf(x);
    y = P * (y * absf(y) - y) + y;
    return y;
}

float cheriCosf(float x) {
    x += PI / 2.f;
    if (x > PI) {
        x -= 2.f * PI;
    }
    return cheriSinf(x);
}

void testforloop() {
    float f;
    for (f = -1.f; f < 1.f; f += 0.2f) {
        WRITE_FLOAT(f, 10);
    }
}

void testmipsmath() {
    float f1 = -1324.123;
    float f2 = 25;
    float f3 = 0.01;
    writeString("Abs: "); writeDigit((int)absf(f1)); writeString(".\n");
    writeString("Sqrt: "); writeDigit((int)sqrtf(f2)); writeString(".\n");
    writeString("Recip: "); writeDigit((int)recipf(f3)); writeString(".\n");
    writeString("Rsqrt: "); writeDigit((int)rsqrtf(f3)); writeString(".\n");
}
