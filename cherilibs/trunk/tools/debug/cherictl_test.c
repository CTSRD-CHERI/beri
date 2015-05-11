/*-
 * Copyright (c) 2012-2013 SRI International
 * Copyright (c) 2012 Robert N. M. Watson
 * Copyright (c) 2015 A. Theodore Markettos
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
 * BERI Debug Test system
 */

#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "macosx.h"
#include "../../include/cheri_debug.h"
#include "cherictl.h"

static void usage(void){
	fprintf(stderr, "berictl_test"
                  " -p path_to_socket"
                  " -f filename"
         					" -c controlfilename\n");
	exit(EXIT_FAILURE);
}


int berictl_docontrol(struct beri_debug *bdp, const char *controlp)
{
  FILE* fp = NULL;

	char str[1024];
	char cmd[128], op1[128], op2[128];
  int len = 0, i;
	fp = fopen(controlp, "r");

  if(fp == NULL){
		fprintf(stderr, "Cannot open control command file %s", controlp);
    return(BERI_DEBUG_USAGE_ERROR);
	}

  int ret = BERI_DEBUG_SUCCESS;
  while (!feof(fp)){
    if (ret != BERI_DEBUG_SUCCESS){
			break; // leave while
		}

    for(i=0; i <= 1024; i++){
			str[i] = fgetc(fp);
      if (str[i] == '\n') {
				str[i] = 0;
        break;
			}
    }
    //fscanf(fp,"%s\n", str); // eat a line
    memset(cmd, 0, 128);
    memset(op1, 0, 128);
    memset(op2, 0, 128);
		len = sscanf(str,"%s %s %s", cmd, op1, op2); // parse first 3 tokens
    fprintf(stderr, "%s => len (cmd,op1,op2): %d (%s,%s,%s)\n", str, len, cmd, op1, op2);

		//Read control
    if((len == 2) && strcmp(cmd, "breakpoint") == 0){
      printf("breakpoint!");
			ret = berictl_breakpoint(bdp, op1, 0);
    } else if((len == 2) && strcmp(cmd, "console") == 0){
      printf("console!");
			ret = berictl_console(NULL, op1, NULL, NULL);
    } else if ((len == 1) && strcmp(cmd, "c0regs") == 0){
      printf("c0regs!");
			ret = berictl_c0regs(bdp);
    } else if ((len == 2) && strcmp(cmd, "lbu") == 0){
      printf("lbu!");
			ret = berictl_lbu(bdp, op1);
		} else if ((len == 2) && strcmp(cmd, "ld") == 0){
      printf("ld!");
			ret = berictl_ld(bdp, op1);
		} else if ((len == 1) && strcmp(cmd, "pause") == 0){
      printf("pause!");
			ret = berictl_pause(bdp);
		}	else if ((len == 1) && strcmp(cmd, "pc") == 0){
      printf("pc!");
			ret = berictl_pc(bdp);
		} else if ((len == 1) && strcmp(cmd, "regs") == 0) {
      printf("regs!");
			ret = berictl_regs(bdp);
		} else if ((len == 1) && strcmp(cmd, "c2regs") == 0) {
      printf("c2regs!");
			ret = berictl_c2regs(bdp);
		} else if ((len == 1) && strcmp(cmd, "resume") == 0) {
      printf("resume!");
			ret = berictl_resume(bdp);
		} else if ((len == 3) && strcmp(cmd, "sb") == 0) {
      printf("sb!");
			ret = berictl_sb(bdp, op1, op2);
		} else if ((len == 3) && strcmp(cmd, "sd") == 0) {
      printf("sd!");
			ret = berictl_sd(bdp, op1, op2);
		} else if ((len == 2) && strcmp(cmd, "setpc") == 0) {
      printf("setpc!");
			ret = berictl_setpc(bdp, op1);
		} else if ((len == 3) && strcmp(cmd, "setreg") == 0) {
      printf("setreg!");
			ret = berictl_setreg(bdp, op1, op2);
		} else if ((len == 1) && strcmp(cmd, "step") == 0) {
      printf("step!");
			ret = berictl_step(bdp);
		} else if ((len == 1) && strcmp(cmd, "unpipeline") == 0) {
      printf("unpipeline!");
			ret = berictl_unpipeline(bdp);
		} else if ((len == 2) && strcmp(cmd, "test") == 0) { //XXX
      printf("test?");
			ret = berictl_test_run(bdp);
			ret = berictl_test_report(bdp);
		} else{
		  fprintf(stderr, "Unrecognized Command: %s (len %d)", cmd, len);
			ret = BERI_DEBUG_USAGE_ERROR;
		}
    fprintf(stderr, "Finished operation\n");
		usleep(200000);
	}

	fprintf(stderr, "Done!\n");  
  fclose(fp);

  return (ret);
}

int main(int argc, char *argv[]) {
	struct beri_debug *bdp = NULL;
	const char *filep = NULL, *controlp = NULL, *pathp = NULL;

	int opt, ret;

	while ((opt = getopt(argc, argv, "c:f:p")) != -1) {
		switch (opt) {
		case 'c':
			controlp = optarg;
			break;
		case 'f':
			filep = optarg;
			break;
		case 'p':
			pathp = optarg;
			break;
		default:
			usage();
		}
	}

	argc -= optind;
	argv += optind;  


	if (argc != 0){ // no more arguments
		usage();
  }

  //------------------------------------------------------------------
  // Open Socket


	if (pathp != NULL)
		ret = beri_debug_client_open_path(&bdp, pathp,
		    BERI_DEBUG_CLIENT_OPEN_FLAGS_SOCKET);
	else
		ret = beri_debug_client_open(&bdp,
		    BERI_DEBUG_CLIENT_OPEN_FLAGS_SOCKET);

	if (ret != BERI_DEBUG_SUCCESS) {
		fprintf(stderr, "Failure opening debugging session: %s\n",
		    beri_debug_strerror(ret));
		exit(EXIT_FAILURE);
	}

  //------------------------------------------------------------------
  // load test file

 
  if(filep == NULL && 0){
    fprintf(stderr, "Expecting test file");
    usage();
  }

  /* ret = berictl_test(bdp, filep); */

	/* printf("HEY, the test is done loading!"); */
	/* if (ret != BERI_DEBUG_SUCCESS) { */
	/* 	fprintf(stderr, "Failure applying operatio: %s\n", */
	/* 	    beri_debug_strerror(ret)); */
	/* 	exit(EXIT_FAILURE); */
	/* } */

  //Control Instructions

  if(controlp == NULL){
    fprintf(stderr, "Expecting Control file");
    usage();
  }

  ret = berictl_docontrol(bdp, controlp);
  
  //------------------------------------------------------------------

  fprintf(stderr, "DONE WITH CONTROL SEQUENCE");

  if (ret == BERI_DEBUG_USAGE_ERROR){
		usage();
  }
	if (ret != BERI_DEBUG_SUCCESS) {
		fprintf(stderr, "Failure applying operation: %s\n",
		    beri_debug_strerror(ret));
		exit(EXIT_FAILURE);
	}
	beri_debug_client_close(bdp);
	exit(EXIT_SUCCESS);
}
