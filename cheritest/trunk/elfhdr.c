/*-
 * Copyright (c) 2016 Michael Roe
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

#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <elf.h>

static unsigned long long flipped;

static unsigned long long flip64(unsigned long long x)
{
char *fp;

  fp = (char *) &flipped;
  fp[7] = x & 0xff;
  fp[6] = (x >> 8) & 0xff;
  fp[5] = (x >> 16) & 0xff;
  fp[4] = (x >> 24) & 0xff;
  fp[3] = (x >> 32) & 0xff;
  fp[2] = (x >> 40) & 0xff;
  fp[1] = (x >> 48) & 0xff;
  fp[0] = (x >> 56) & 0xff;

  return flipped;
}

int main(int argc, char **argv)
{
Elf64_Ehdr h;
Elf64_Phdr ph;
Elf64_Shdr sh0;
Elf64_Shdr sh1;
Elf64_Shdr sh2;
struct stat stats;
int i;
char *fname_in;
char *fname_out;
FILE *f_in;
FILE *f_out;
static char strtab[] = {0, '.', 's', 'h', 's', 't', 'r', 't', 'a', 'b', 0,
    '.', 'd', 'a', 't', 'a', 0};

  if (argc < 3)
  {
    fprintf(stderr, "Usage: elfhdr <input file> <output file>\n");
    return -1;
  }

  fname_in = argv[1];
  fname_out = argv[2];

  if (stat(fname_in, &stats) != 0)
  {
    fprintf(stderr, "Couldn't fstat %s\n", fname_in);
    return -1;
  }

  f_in = fopen(fname_in, "r");
  if (f_in == NULL)
  {
    fprintf(stderr, "Couldn't open %s\n", fname_in);
    return -1;
  }

  f_out = fopen(fname_out, "w");
  if (f_out == NULL)
  {
    fprintf(stderr, "Couldn't open %s\n", fname_out);
    return -1;
  }

  memset((void *) &h, 0, sizeof(h));
  h.e_ident[0] = ELFMAG0;
  h.e_ident[1] = ELFMAG1;
  h.e_ident[2] = ELFMAG2;
  h.e_ident[3] = ELFMAG3;
  h.e_ident[EI_CLASS] = ELFCLASS64;
  h.e_ident[EI_DATA] = ELFDATA2MSB;
  h.e_ident[EI_VERSION] = EV_CURRENT;
  h.e_type = htons(ET_EXEC);
  h.e_machine = htons(EM_MIPS);
  h.e_version = htonl(EV_CURRENT);
  h.e_entry = flip64(0x9000000040000000);
  h.e_phoff = flip64(sizeof(h));
  h.e_shoff = flip64(sizeof(h)+sizeof(ph));
  h.e_flags = htonl(0x60000001);
  h.e_ehsize = htons(sizeof(h));
  h.e_phentsize = htons(sizeof(ph));
  h.e_phnum = htons(1);
  h.e_shentsize = htons(sizeof(sh0));
  h.e_shnum = htons(3);
  h.e_shstrndx = htons(2);
  
  memset((void *) &ph, 0, sizeof(ph));
  ph.p_type = htonl(PT_LOAD);
  ph.p_flags = htonl(PF_R | PF_W | PF_X);
  ph.p_offset = flip64(1024);
  ph.p_vaddr = flip64(0x9000000040000000);
  ph.p_paddr = flip64(0x40000000);
  ph.p_filesz = flip64(stats.st_size);
  ph.p_memsz = flip64(stats.st_size);
  ph.p_align = flip64(1024);

  memset((void *) &sh0, 0, sizeof(sh0));
  sh0.sh_name = 0;
  sh0.sh_type = htonl(SHT_NULL);
  sh0.sh_size = flip64(0);

  memset((void *) &sh1, 0, sizeof(sh2));
  sh1.sh_name = htonl(11);
  sh1.sh_type = htonl(SHT_PROGBITS);
  sh1.sh_flags = flip64(SHF_WRITE | SHF_ALLOC | SHF_EXECINSTR);
  sh1.sh_addr = flip64(0x9000000040000000);
  sh1.sh_offset = flip64(1024);
  sh1.sh_size = flip64(stats.st_size);
  sh1.sh_addralign = flip64(8);

  memset((void *) &sh2, 0, sizeof(sh2));
  sh2.sh_name = htonl(1);
  sh2.sh_type = htonl(SHT_STRTAB);
  sh2.sh_offset = flip64(sizeof(h)+sizeof(ph)+3*sizeof(sh1));
  sh2.sh_size = flip64(sizeof(strtab));
  sh2.sh_entsize = flip64(0);

  fwrite((void *) &h, sizeof(h), 1, f_out);
  fwrite((void *) &ph, sizeof(ph), 1, f_out);
  fwrite((void *) &sh0, sizeof(sh0), 1, f_out);
  fwrite((void *) &sh1, sizeof(sh1), 1, f_out);
  fwrite((void *) &sh2, sizeof(sh2), 1, f_out);
  fwrite(strtab, sizeof(strtab), 1, f_out);

  fseek(f_out, 1024, SEEK_SET);
  for (i=0; i<stats.st_size; i++)
    fputc(fgetc(f_in), f_out);

  fclose(f_in);
  fclose(f_out);

  return 0;
}
