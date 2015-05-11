/*-
 * Copyright (c) 2015 Matthew Naylor
 * All rights reserved.
 *
 * This software was developed by the University of Cambridge Computer
 * Laboratory as part of the Rigorous Engineering of Mainstream Systems (REMS)
 * project, funded by EPSRC grant EP/K008528/1.
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
//   3) RMO
//   4) SC-SA
//   5) TSO-SA
//   6) PSO-SA
//   7) RMO-SA

#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <string.h>

// ============================================================================
// Constants
// ============================================================================

#define MAX_REGS     64
#define MAX_THREADS  4
#define MAX_INSTRS   1024

// ============================================================================
// Types
// ============================================================================

typedef unsigned char Reg;
typedef unsigned int Data;
typedef unsigned long long Addr;
typedef unsigned char ThreadId;
typedef unsigned char Model;

typedef enum {
    LOAD
  , STORE
} Op;

typedef struct {
  Op op;
  ThreadId tid;
  Reg dest;
  Addr addr;
  Data data;
} Instr;

// ============================================================================
// Globals
// ============================================================================

// Register file for each thread
Data regFile[MAX_THREADS][MAX_REGS];

// Instruction trace
Instr trace[MAX_INSTRS];
int numInstrs = 0;

// Have we been initialised?
int init = 0;

// Interface to Axe tool
int toAxe[2];   // (0 is read end, 1 is write end)
int fromAxe[2];

// ============================================================================
// Functions
// ============================================================================

const char* modelText(Model model)
{
  switch (model) {
    case 0: return "sc";
    case 1: return "tso";
    case 2: return "pso";
    case 3: return "rmo";
    case 4: return "sc-sa";
    case 5: return "tso-sa";
    case 6: return "pso-sa";
    case 7: return "rmo-sa";
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
    execlp("Axe", "Axe", "-i", modelText(model), NULL);
    fprintf(stderr, "Failed to exec 'Axe' process.\n");
    fprintf(stderr, "Please add 'Axe' to your PATH.\n");
    abort();
  }
}

void axeInit(Model model)
{
  numInstrs = 0;
  if (!init) {
    axeConnect(model);
    init = 1;
  }
}

void axeLoad(ThreadId tid, Reg dest, Addr addr)
{
  Instr instr;
  instr.op   = LOAD;
  instr.tid  = tid;
  instr.dest = dest;
  instr.addr = addr;
  trace[numInstrs++] = instr;
}

void axeStore(ThreadId tid, Data data, Addr addr)
{
  Instr instr;
  instr.op   = STORE;
  instr.tid  = tid;
  instr.addr = addr;
  instr.data = data;
  trace[numInstrs++] = instr;
}

void axeSetReg(ThreadId tid, Reg dest, Data data)
{
  regFile[tid][dest] = data;
}

unsigned char axeCheck(unsigned char showTrace)
{
  int i;
  char buffer[1024];
  for (i = 0; i < numInstrs; i++) {
    Instr instr = trace[i];
    if (instr.op == LOAD) {
      snprintf(buffer, sizeof(buffer), "%i: v%lli == %i\n",
        instr.tid, instr.addr, regFile[instr.tid][instr.dest]);
    }
    else if (instr.op == STORE) {
      snprintf(buffer, sizeof(buffer), "%i: v%lli := %i\n",
        instr.tid, instr.addr, instr.data);
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
