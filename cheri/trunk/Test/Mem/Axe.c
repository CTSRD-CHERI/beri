/* Copyright 2015 Matthew Naylor
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
 * ("MRC2"), as part of the DARPA MRC research programme.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream
 * Systems (REMS) project, funded by EPSRC grant EP/K008528/1.
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

// Interface to Axe tool for checking shared memory models.
//
// Models are:
//   0) SC
//   1) TSO
//   2) PSO
//   3) WMO
//   4) POW
//   5) TIM (WMO ignoring dependecies, e.g. time-based coherence)

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>
#include <assert.h>

// ============================================================================
// Constants
// ============================================================================

#define MAX_THREADS  4
#define MAX_INSTRS   10000

// ============================================================================
// Types
// ============================================================================

typedef int Data;
typedef unsigned long long Addr;
typedef unsigned char ThreadId;
typedef unsigned char Model;

typedef enum {
    LOAD
  , STORE
  , SYNC
  , RMW
} Op;

typedef struct {
  Op op;
  ThreadId tid;
  Addr addr;
  Data data;
  Data data2;
  int success;
  int reqTime, respTime;
} Instr;

// ============================================================================
// Globals
// ============================================================================

// Instruction trace
Instr trace[MAX_INSTRS];
int numInstrs = 0;
int lastResponse[MAX_THREADS];

// Have we been initialised?
int init = 0;

// Interface to Axe tool
int toAxe[2];   // (0 is read end, 1 is write end)
int fromAxe[2];

// ============================================================================
// Functions
// ============================================================================

const char* modelText(Model model, int* ignoreDeps)
{
  // Ignore depedencies between memory operations?
  *ignoreDeps = 0;
  switch (model) {
    case 0: return "sc";
    case 1: return "tso";
    case 2: return "pso";
    case 3: return "wmo";
    case 4: return "pow";
    case 5: *ignoreDeps = 1; return "wmo";
  }
  return "";
}

void axeConnect(Model model)
{
  pipe(toAxe);
  pipe(fromAxe);

  if (fork() == 0) {
    dup2(toAxe[0], STDIN_FILENO);
    dup2(fromAxe[1], STDOUT_FILENO);
    int ignoreDeps;
    char* m = modelText(model, &ignoreDeps);
    if (ignoreDeps)
      execlp("axe", "axe", "check", m, "-", "-i", NULL);
    else
      execlp("axe", "axe", "check", m, "-", NULL);
    fprintf(stderr, "Failed to exec 'axe' process.\n");
    fprintf(stderr, "Please add 'axe' to your PATH.\n");
    abort();
  }
}

void axeInit(Model model)
{
  int i;
  numInstrs = 0;
  if (!init) {
    axeConnect(model);
    init = 1;
  }
  for (i = 0; i < MAX_THREADS; i++)
    lastResponse[i] = -1;
}

void axeLoad(ThreadId tid, Addr addr, int time)
{
  Instr instr;
  instr.op   = LOAD;
  instr.tid  = tid;
  instr.addr = addr;
  instr.data = -1;
  instr.reqTime = time;
  instr.respTime = -1;
  assert(numInstrs < MAX_INSTRS);
  trace[numInstrs++] = instr;
}

void axeStore(ThreadId tid, Data data, Addr addr, int time)
{
  Instr instr;
  instr.op   = STORE;
  instr.tid  = tid;
  instr.addr = addr;
  instr.data = (int) data;
  instr.reqTime = time;
  instr.respTime = -1;
  assert(numInstrs < MAX_INSTRS);
  trace[numInstrs++] = instr;
}

void axeRMW(ThreadId tid, Data data, Addr addr, int reqTime)
{
  Instr instr;
  instr.op    = RMW;
  instr.tid   = tid;
  instr.addr  = addr;
  instr.data  = -1;
  instr.data2 = (int) data;
  instr.success = 0;
  instr.reqTime = reqTime;
  instr.respTime = -1;
  assert(numInstrs < MAX_INSTRS);
  trace[numInstrs++] = instr;
}

void axeSync(ThreadId tid, int time)
{
  Instr instr;
  instr.op   = SYNC;
  instr.tid  = tid;
  instr.reqTime = time;
  instr.respTime = -1;
  assert(numInstrs < MAX_INSTRS);
  trace[numInstrs++] = instr;
}

void axeResponse(ThreadId tid, Data data, int time)
{
  int i = lastResponse[tid]+1;
  for (;;) {
    assert(i < numInstrs);
    if (trace[i].tid == tid) {
      if (trace[i].op == LOAD) {
        trace[i].data = (int) data;
        trace[i].respTime = time;
        lastResponse[tid] = i;
        break;
      }
      else if (trace[i].op == RMW) {
        if (trace[i].data == -1) {
          trace[i].data = (int) data;
          trace[i].respTime = time;
          lastResponse[tid] = i-1;
        } else {
          assert(data == 0 || data == 1);
          if (data == 1) trace[i].success = 1;
          lastResponse[tid] = i;
        }
        break;
      }
    }
    i++;
  }
}

void printTimestamps(char* buff, int buffLen, Instr instr)
{
  char numStr[32];
  snprintf(numStr, sizeof(numStr), "%i", instr.respTime);
  snprintf(buff, buffLen, "");
  if (instr.reqTime >= 0) {
    snprintf(buff, buffLen, "@ %i:%s", instr.reqTime,
      instr.respTime >= 0 ? numStr : "");
  }
}

unsigned char axeCheck(unsigned char showTrace)
{
  int i;
  char buffer[1024];
  char buffer2[1024];
  for (i = 0; i < numInstrs; i++) {
    Instr instr = trace[i];
    printTimestamps(buffer2, sizeof(buffer2), instr);
    if (instr.op == LOAD || (instr.op == RMW && instr.success == 0)) {
      if (instr.data == -1)
        continue;
      else {
        snprintf(buffer, sizeof(buffer), "%i: v%lli == %i %s\n",
          instr.tid, instr.addr, instr.data, buffer2);
      }
    }
    else if (instr.op == STORE) {
      snprintf(buffer, sizeof(buffer), "%i: v%lli := %i %s\n",
        instr.tid, instr.addr, instr.data, buffer2);
    }
    else if (instr.op == SYNC) {
      snprintf(buffer, sizeof(buffer), "%i: sync %s\n", instr.tid, buffer2);
    }
    else if (instr.op == RMW) {
      snprintf(buffer, sizeof(buffer), "%i: { v%lli == %i ; v%lli := %i } %s\n",
        instr.tid, instr.addr, instr.data, instr.addr, instr.data2, buffer2);
    }
    write(toAxe[1], buffer, strlen(buffer));
    if (showTrace) printf("%s", buffer);
  }
  write(toAxe[1], "check\n", 6);
  read(fromAxe[0], buffer, 3);
  buffer[4] = '\0';
  if (buffer[0] == 'O') return 1;
  else if (buffer[0] == 'N') return 0;
  else {
    printf("Unexpected response from 'Axe': %s\n", buffer);
    abort();
  }
  return 0;
}
