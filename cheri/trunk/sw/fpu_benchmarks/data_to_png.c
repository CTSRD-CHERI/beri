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

#include "std.h"

#include <IL/il.h>

#include <stdio.h>
#include <stdlib.h>

int main(int argc, char* argv[]) {
    if (argc != 3) {
        printf("Usage: %s <input data file> <output image file>", argv[0]);
    }

    byte* img = malloc(IMG_ARRAY_LENGTH);
    ilInit();

    uint pos = 0;
    FILE* dataFile = fopen(argv[1], "r");
    while (fscanf(dataFile, "%2hhx", &(img[pos++])) == 1) { }
    fclose(dataFile);

    ilTexImage(IMG_WIDTH, IMG_HEIGHT, 0, 3, IL_RGB, IL_UNSIGNED_BYTE, img);
    ilSaveImage(argv[2]);
}
