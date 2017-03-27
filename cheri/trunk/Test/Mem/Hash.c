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

#include <stdlib.h>
#include <stdio.h>

// ============================================================================
// Types
// ============================================================================

typedef unsigned int *Val;

typedef unsigned long long Key;

typedef unsigned long long Timestamp;

typedef struct {
  Timestamp timestamp;
  Key key;
  Val val;
} HashEntry;

typedef struct {
  int keySize;
  int valSize;
  Timestamp timestamp;
  int maxEntries;
  HashEntry* entries;
} HashTable;

// ============================================================================
// Globals
// ============================================================================

// Global hash table
HashTable table;

// Hsah table been initialised?
int initialised = 0;

// ============================================================================
// Functions
// ============================================================================

// Allocate hash table capable of holding a given number of entries.
// The key-size and val-size are specified as multiples of 32-bit words.
// Must be called before any other functions below.
void hashInit(int n, int keySize, int valSize)
{
  int i;
  if (initialised) {
    table.timestamp++;
  }
  else {
    table.keySize = keySize;
    table.valSize = valSize;
    table.timestamp = 1;
    table.maxEntries = n;
    table.entries = malloc(sizeof(HashEntry) * n);
    for (i = 0; i < n; i++) {
      table.entries[i].timestamp = 0;
      table.entries[i].val = malloc(valSize * 4);
    }
    initialised = 1;
  }
}

// Hash function
unsigned int hash(Key key)
{
  unsigned int x, y;
  int i;

  x = key;
  y = 0;
  while (x > 0) {
    y = y ^ (x % table.maxEntries);
    x = x / table.maxEntries;
  }
  return y % table.maxEntries;
}

// Clear hash table
void hashClear()
{
  table.timestamp++;
}

// Insert into hash table
void hashInsert(Key key, Val val)
{
  int i, j, k;
  unsigned int h = hash(key);

  for (i = 0; i < table.maxEntries; i++) {
    j = (i+h) % table.maxEntries;
    HashEntry entry = table.entries[j];
    if (entry.timestamp != table.timestamp ||
        entry.key == key) {
      entry.timestamp = table.timestamp;
      entry.key = key;
      for (k = 0; k < table.valSize; k++)
        entry.val[k] = val[k];
      table.entries[j] = entry;
      return;
    }
  }
  printf("Hash table full\n");
  abort();
}

// Lookup hash table
void hashLookup(Val result, Key key)
{
  int i, j, k;
  unsigned int h = hash(key);

  for (k = 0; k < table.valSize; k++)
    result[k] = 0;

  for (i = 0; i < table.maxEntries; i++) {
    j = (i+h) % table.maxEntries;
    HashEntry entry = table.entries[j];
    if (entry.timestamp == table.timestamp) {
      if (entry.key == key) {
        for (k = 0; k < table.valSize; k++)
          result[k] = entry.val[k];
        return;
      }
    }
    else {
      return;
    }
  }
}
