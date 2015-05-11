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

static inline float imageXInMandelbrot(uint x) {
    return SCALE * ((float)x / (float)IMG_WIDTH - 0.5f) + CEN_X;
}

static inline float imageYInMandelbrot(uint y) {
    return SCALE * ((float)y / (float)IMG_HEIGHT - 0.5f) + CEN_Y;
}

void calculateMandelbrotVectorised() {
    byte* img = cheriMalloc(IMG_ARRAY_LENGTH);

    TimeUnit start = startTiming();
    
    v4sf i = newV4sf(0, 1, 2, 3);
    v4sf j = replicateToV4sf(0);
    float next_i = 4, next_j = 0;
    v4sf x0 = newV4sf(imageXInMandelbrot(0), 
                      imageXInMandelbrot(1),
                      imageXInMandelbrot(2),
                      imageXInMandelbrot(3));
    v4sf y0 = replicateToV4sf(imageYInMandelbrot(next_j));

    uint itemI, itemJ;
    float itemSumSq, itemIterations, itemX, itemY;
    v4sf x = x0, y = y0, xtemp, xsq = x * x, ysq = y * y, sumsq;
    v4sf iterations = replicateToV4sf(0);
    v4sf oneVector = replicateToV4sf(1);
    v4sf twoVector = replicateToV4sf(2);

    while (next_j < IMG_HEIGHT) {
        xsq = x * x;
        ysq = y * y;
        sumsq = xsq + ysq;

        xtemp = xsq - ysq + x0;
        y = twoVector * x * y + y0;
        x = xtemp;
        for (uint item = 0; item < 4; ++item) {
            itemSumSq = getV4sfElement(sumsq, item);
            itemIterations = (uint)getV4sfElement(iterations, item);
            if (itemSumSq >= 4.0f || itemIterations >= MAX_ITERATIONS) {
                itemI = (uint)getV4sfElement(i, item);
                itemJ = (uint)getV4sfElement(j, item);

                byte red = 0;
                byte green = 0x86 - (itemIterations * 0x86) / MAX_ITERATIONS;
                byte blue = 0xFF - (itemIterations * 0xFF) / MAX_ITERATIONS;
                setPixel(img, itemI, itemJ, red, green, blue);

                if (next_i > IMG_WIDTH) {
                    next_i = 0.0f;
                    next_j = next_j + 1.0f;
                }
                itemI = next_i;
                next_i = next_i + 1.0f;
                itemJ = next_j;
                i[item] = itemI;
                j[item] = itemJ;
                itemX = imageXInMandelbrot(itemI);
                itemY = imageYInMandelbrot(itemJ);
                x0[item] = itemX;
                y0[item] = itemY;
                x[item] = itemX;
                y[item] = itemY;
                iterations[item] = 0;
            }
        }
        iterations += oneVector;
    }
    finishTiming(start);

    outputImage("MANDELBROT", img);
}
