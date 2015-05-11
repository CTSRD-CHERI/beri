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
#include "mandelbrot_scalar.h"
#include "project_scalar.h"
#include "data_scalar.h"
#include "mandelbrot_vectorised.h"
#include "project_vectorised.h"
#include "data_vectorised.h"
#include "std.h"

#include "mipsmath.h"

static inline byte exceptionCode(uint cause) {
    return (cause >> 2) & 0x3F;
}

char* const exceptionCodeStrings[] = {
    "interrupt",
    "TLB modification",
    "TLB load or instruction fetch",
    "TLB store",
    "load address error",
    "store address error",
    "instruction fetch bus error",
    "data bus error",
    "syscall",
    "breakpoint",
    "reserved instruction",
    "coprocessor unusable",
    "arithmetic overflow",
    "trap",
    "(RESERVED)",
    "float point exception",
    "(IMPLEMENTATION DEPENDENT)",
    "(IMPLEMENTATION DEPENDENT)",
    "precise cop2 exception",
    "TLB read inhibit",
    "TLB execute inhibit",
    "(RESERVED)",
    "(RESERVED)",
    "MDMX unusable",
    "watchhi/watchlo reference",
    "machine check",
    "thread exception",
    "dsp"
};

ulong handle_exception(ulong target, uint cause, ulong badvaddr) {
    writeString("Exception occured at: ");
    writeHex(target);
    writeString(".\n");
    byte code = exceptionCode(cause);
    writeString("Code: ");
    writeDigit(code);
    writeString(".\n");
    writeString(". Meaning: ");
    writeString(exceptionCodeStrings[code]);
    writeString(".\n");
    if ((code >= 1 && code <= 5) || code == 19 || code == 20) {
        writeString("\tBad virtual address: ");
        writeHex(badvaddr);
        writeString(".\n");
    }
    if (code == 8) {
        return target + 4;
    }
    else {
        while (1) { };
    }
    return target;
}

int main(void)
{
    writeString("Hi!\n");
    writeString("Performing scalar tests: \n");
    /*writeString("Running simple array tests...\n");*/
    /*runDataTestsScalar();*/
    writeString("Calculating Mandelbrot...\n");
    calculateMandelbrotScalar();
    writeString("Doing projection benchmark...\n");
    runProjectionBenchmarkScalar();
    writeString("Done. Performing vectorised tests: \n");
    /*writeString("Running simple array tests...\n");*/
    /*runDataTestsVectorised();*/
    writeString("Calculating Mandelbrot...\n");
    calculateMandelbrotVectorised();
    writeString("Doing projection benchmark...\n");
    runProjectionBenchmarkVectorised();
    writeString("Done. Have a nice day!\n");
    while (1) {}
    return 0;
}
