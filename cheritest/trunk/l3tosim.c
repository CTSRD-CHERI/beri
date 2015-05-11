/*-
 * Copyright (c) 2014 Michael Roe
 * All rights reserved.
 *
 * This software was developed by SRI International and the University of
 * Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
 * ("CTSRD"), as part of the DARPA CRASH research programme.
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

/*
 * l3tosim - convert register dump files between the format output by the L3
 * MIPS simulator, and the input format expected by the CHERI test suite.
 */

#include <stdio.h>
#include <string.h>

int main(int argc, char **argv)
{
char buff[1023];
int len;
int reg_num;
int core = 0;

  while (fgets(buff, sizeof(buff), stdin) != NULL)
  {
    len = strlen(buff);
    if (buff[len - 1] == '\n')
    {
      len--;
      buff[len] = '\0';
    }
    if ((strncmp(buff, "Reg ", 4) == 0) &&
      (strstr(buff, "<-") == (char *) 0))
    {
      buff[6] = '\0';
      reg_num = atoi(buff + 4);
      printf("DEBUG MIPS REG %2d 0x%s\n", reg_num, buff + 7);
    }
    else if ((strncmp(buff, "PC ", 3) == 0) && (core == 0))
    {
      printf("DEBUG MIPS PC 0x%s\n", buff + 7);
    }
    else if (strncmp(buff, "Core = ", 7) == 0)
    {
      core = strtol(buff + 7, NULL, 0);
      printf("DEBUG MIPS COREID %d\n", core);
    }
    else if (strncmp(buff, "DEBUG CAP", 9) == 0)
    {
      printf("%s\n", buff);
    }
  }

  return 0;
}
