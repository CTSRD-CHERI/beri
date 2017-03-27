/*-
 * Copyright (c) 2014 Alexandre Joannou
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

// libs
#include "lock.h"
#include "core.h"
#include "semaphore.h"
#include "uart.h"
#include "multi_test.h"

// tests
#include "scatter_gather.h"
#include "shared_array.h"
#include "parallel_sort.h"
#include "merge_sort.h"

///////////////////////////////
// global (shared) variables //
///////////////////////////////
volatile int go = 0; // used for synchronizing cores before first semaphore gets initialized
semaphore_t menu_semaphore; // semaphore to wait for the end of the menu
semaphore_t test_semaphore; // semaphore to wait for the end of the test
semaphore_t stat_semaphore; // semaphore to wait for the end of the stats display

test_function_t current_test[MAX_CORE];

volatile int end = 0; // control the end of the main loop

void menu ()
{
    // acquire display lock
    uart_lock_acquire();

    // display the menu
    uart_puts("\n");
    uart_puts("=======================\n");
    uart_puts("===== multi-cheri =====\n");
    uart_puts("=======================\n");
    uart_puts("\n");
    uart_puts("  core total ...... "); uart_putd(core_total()); uart_putc('\n');
    uart_puts("\n");
    uart_puts("  menu :\n");
    //uart_puts("  - A to display le duck\n");
    //uart_puts("  - B to kill le duck\n");
    uart_puts("  - C to multi-print strings\n");
    uart_puts("  - D to multi-print strings (locked access to UART)\n");
    uart_puts("  - E to scatter/gather test\n");
    uart_puts("  - F to shared array test\n");
    uart_puts("  - S to parallel sort test\n");
    uart_puts("  - M to merge sort test\n");
    uart_puts("  - Q to quit\n");
    uart_puts("\n");
    uart_puts("=======================\n");
    uart_puts("> ");
    // get user input
    char c = uart_getc();
    char select = c;
    // empty user input buffer
    while (c != '\n')
        c = uart_getc();
    // init test vector
    multi_default_init (&current_test);
    switch(select)
    {
        case 'A':
            uart_puts("____ >o_/ ____\n");
        break;
        case 'B':
            uart_puts("____ >x_/ ____\n");
        break;
        case 'C':
            multi_print_init (&current_test);
        break;
        case 'D':
            multi_print_locked_init (&current_test);
        break;
        case 'E':
            scatter_gather_init (&current_test);
        break;
        case 'F':
            shared_array_init (&current_test);
        break;
        case 'S':
            parallel_sort_main (&current_test);
        break;
        case 'M':
            merge_sort_init (&current_test);
        break;
        case 'Q':
        case 'q':
            uart_putc('\n');
            end = 1;
        break;
        default :
            uart_putc('\n');
        break;
    }
    core_sync();
    // release uart lock
    uart_lock_release();
}

int main ()
{
    // traces & stats variables
    unsigned long long counter_value_start = 0;
    unsigned long long counter_value_end = 0;
    unsigned long long total_cycles = 0;

    // synchronizing cores
    if (core_id() == 0)
    {
        // init uart lock
        uart_lock_init();
        // reset the next end menu checkpoint
        semaphore_init(&menu_semaphore, core_total());
        // let every one start
        go = 1;
        core_sync();
    }
    else while (!go) {core_sync();}

    // main loop
    while (!end)
    {
        if (core_id() == 0)
        {
            // run the menu
            menu();
            // reset the next end test checkpoint
            semaphore_init(&test_semaphore, core_total());
            // reset the next end stat display checkpoint
            semaphore_init(&stat_semaphore, core_total());
        }
        // end menu checkpoint, wait for everyone
        semaphore_wait(&menu_semaphore);

        // init start counter variable
        counter_value_start = core_counter();

				
				/*if (core_id() == 0)
				{
					uart_putd(counter_value_start);
					uart_putc('\n');
				}*/
        // branch to dedicated test function
        (current_test[core_id()])();
				
        // init end counter variable
        counter_value_end = core_counter();
        /*if (core_id() == 0)
				{
        	uart_putd(counter_value_end);
        	uart_putc('\n');
       	}*/
        total_cycles = (counter_value_end - counter_value_start);

        if (core_id() == 0)
        {
            // reset the next end menu checkpoint
            semaphore_init(&menu_semaphore, core_total());
        }
        // end test checkpoint, wait for everyone
        semaphore_wait(&test_semaphore);
        // display post-test traces
        uart_lock_acquire();
        uart_puts("---- core ");
        uart_putd(core_id());
        uart_puts(" : ");
        uart_putd(total_cycles);//total_cycles);
        uart_puts(" cycles\n");
        uart_lock_release();
        // end display stat checkpoint, wait for everyone
        semaphore_wait(&stat_semaphore);
        core_sync();
    }
    return 0;
}
