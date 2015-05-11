/*-
 * Copyright (c) 2013, 2014 Alexandre Joannou
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

#include <stdlib.h>

typedef struct {
    unsigned char ** data;
    unsigned int elementByteSize;
    unsigned int size;
    unsigned int ratio;
} mem_t;

unsigned long long mem_create(unsigned int * memSize,
                              unsigned int * readElementSize,
                              unsigned int * writeElementSize)
{
    mem_t * m = (mem_t*) malloc (sizeof(mem_t));

    m->elementByteSize = ((*readElementSize)%8)    ?
                         ((*readElementSize)/8) + 1:
                         ((*readElementSize)/8)    ;

    m->size = *memSize;

    m->ratio = ((*writeElementSize)%(*readElementSize))    ?
               ((*writeElementSize)/(*readElementSize)) + 1:
               ((*writeElementSize)/(*readElementSize))    ;

    m->data = (unsigned char **) malloc (*memSize * sizeof(unsigned char *));

    unsigned int i;
    for (i = 0; i < *memSize; i++)
    {
        m->data[i] = (unsigned char *) malloc (m->elementByteSize * sizeof(unsigned char));
    }

    return (unsigned long long) m;

}

void mem_read(unsigned int * rdata_return, unsigned long long mem_ptr, unsigned int * rindex)
{
    mem_t * m = (mem_t*) mem_ptr;
    unsigned int i;
    for (i = 0; i < m->elementByteSize; i++)
    {
        ((unsigned char*)(rdata_return))[i] = m->data[*rindex][i];
    }
}

void mem_write(unsigned long long mem_ptr, unsigned int * windex, unsigned int * wdata)
{
    mem_t * m = (mem_t*) mem_ptr;

    unsigned int base = (m->ratio)*(*windex);

    unsigned int i, j;
    for (i = 0; i < m->ratio; i++)
    {
        for (j = 0; j < m->elementByteSize; j++)
        {
            m->data[base+i][j] = ((unsigned char *)(wdata))[(m->elementByteSize)*i+j];
        }
    }
}

// TODO need testing
void mem_write_be(unsigned long long mem_ptr, unsigned int * wbe, unsigned int * windex, unsigned int * wdata)
{
    mem_t * m = (mem_t*) mem_ptr;

    unsigned int base = (m->ratio)*(*windex);

    unsigned int i, j;
    for (i = 0; i < m->ratio; i++)
    {
        for (j = 0; j < m->elementByteSize; j++)
        {
            if((*wbe)&(1<<((m->elementByteSize)*i+j)))
                m->data[base+i][j] = ((unsigned char *)(wdata))[(m->elementByteSize)*i+j];
        }
    }
}

void mem_clean(unsigned long long mem_ptr)
{
    mem_t * m = (mem_t*) mem_ptr;
    unsigned int i;
    for (i = 0; i < m->size; i++)
    {
        free(m->data[i]);
    }
    free(m);
}
