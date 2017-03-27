/*-
 * Copyright (c) 2016 Jonathan Woodruff
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
 * @BERI_LICENSE_HEADER_START@
 *
 * Licensed to BERI Open Systems C.I.C (BERI) under one or more contributor
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

#include "merge_sort.h"
#include "core.h"
#include "uart.h"
#include "semaphore.h"

#define ARRAY_SIZE 100
volatile unsigned int array[ARRAY_SIZE];
semaphore_t barrier_semaphore; // semaphore to wait
volatile int mergeGo = 0;

inline void sync()
{
   // synchronizing cores
    if (core_id() == 0)
    {
        // init uart lock
        uart_lock_init();
        // reset the next end menu checkpoint
        semaphore_init(&barrier_semaphore, core_total());
        // let every one start
        mergeGo = 1;
        core_sync();
    }
    else while (!mergeGo) {core_sync();}
    semaphore_wait(&barrier_semaphore);
    mergeGo = 0;
}

mergesortP()
{
	int i;
	int j;
	int cx = core_id();
	int ctot = core_total();
	sync();
	mergesort(array, (ARRAY_SIZE/ctot)*cx, (ARRAY_SIZE/ctot)*(cx+1)-1);
	sync();
	i = 0x1;
	for (j=2; j<=ctot; j=j<<1){
		if ((cx & i)==0) {
			merge(array, (ARRAY_SIZE/ctot)*cx, (ARRAY_SIZE/ctot)*(cx+j)-1, (ARRAY_SIZE/ctot)*(cx+j/2)-1);
		}
		i = (i<<1)|0x1;
		sync(cx);
	}
}

mergesort(int a[], int low, int high)
{
	int mid;
	if(low<high) {
		mid=(low+high)/2;
		mergesort(a,low,mid);
		mergesort(a,mid+1,high);
		merge(a,low,high,mid);
	}
	return(0);
}

merge(int a[], int low, int high, int mid)
{
	int i, j, k;
	i=low;
	j=mid+1;
	k=low;
	while((i<=mid)&&(j<=high)) {
		if(a[i]<a[j]) {
			array[k]=a[i];
			k++;
			i++;
		}
		else {
			array[k]=a[j];
			k++;
			j++;
		}
	}
	while(i<=mid) {
		array[k]=a[i];
		k++;
		i++;
	}
	while(j<=high) {
		array[k]=a[j];
		k++;
		j++;
	}
	for(i=low;i<k;i++) {
		a[i]=array[i];
	}
} 

int merge_sort_main()
{
	int i = 0;
	int j = ARRAY_SIZE/core_total();
	int index = (ARRAY_SIZE/core_total()) * core_id();
	// Initialisation 
	for (i=0; i<j; i++) {		// Just generate an array to sort.
		int tmp = (index + i) & 0x1;
		if (!tmp) // Even elements are reverse sorted
			array[index + i] = (index + i) & 0xF;
		else					// Odd elements are in order
			array[index + i] = (ARRAY_SIZE - (index + i)) & 0xF;
	}

	// Divide and Conquer
	mergesortP();
	return 0;
}

void merge_sort_init (test_function_t * mtest)
{
		int i;
    for (i = 0; i < (core_total()); i++)
        mtest[i] = &merge_sort_main;
}

