#
# Copyright (c) 2012 Simon W. Moore
# Copyright (c) 2013-2014 Bjoern A. Zeeb
# Copyright (c) 2013-2014 A. Theodore Markettos
# Copyright (c) 2013-2014 Colin Rothwell
# Copyright (c) 2014 Robert M. Norton
# Copyright (c) 2014 Jonathan Woodruff
# Copyright (c) 2014 Alan A. Mujumdar
# Copyright (c) 2014 Michael Roe
# Copyright (c) 2014 Alex Horsman
# Copyright (c) 2014 SRI International
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# @BERI_LICENSE_HEADER_START@
#
# Licensed to BERI Open Systems C.I.C. (BERI) under one or more contributor
# license agreements.  See the NOTICE file distributed with this work for
# additional information regarding copyright ownership.  BERI licenses this
# file to you under the BERI Hardware-Software License, Version 1.0 (the
# "License"); you may not use this file except in compliance with the
# License.  You may obtain a copy of the License at:
#
#   http://www.beri-open-systems.org/legal/license-1-0.txt
#
# Unless required by applicable law or agreed to in writing, Work distributed
# under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
# CONDITIONS OF ANY KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations under the License.
#
# @BERI_LICENSE_HEADER_END@
#

##############################################################################
# Makefile to build an Altera FPGA system designed in Qsys and Quartus
##############################################################################
# Updated and tested on Quartus 16.0.0
#
# Notes:
# - Use the IDEs (Quartus and Qsys) to setup the system including
#   various parameters.
# - Use Quartus IDE to generate the programming chain file (.cdf) using
#   the graphical download tool
# - This makefile is more of a build script, i.e. it does not do incremental
#   builds but is useful to build everything

# The following six envrionment variables are project specific
SHELL=bash
QUARTUS_PROJECT=DE4_BERI
QUARTUS_PROJECT_VERSION=DE4_BERI
QSYS_PROJECT=DE4_SOC
FPGA="Stratix IV"
# Version of Quartus this has been tested on:
QUARTUS_VERSION?='16.0.0'
# User specific temporary area to avoid collisions
TEMP=/tmp/$(USER)
TMP=$(TEMP)
# Bluespec standard Verilog libraries from BLUESPECDIR environment variable
BLUESPEC_VERILOG=$(BLUESPECDIR)/Verilog
# CHERI build specific:
ifdef CHERI2
CHERI_DIR=../../../../cheri2/trunk/
else
CHERI_DIR=../../
endif
# project specific peripherals for Qsys
CHERILIBSDIR=../../../../cherilibs/trunk
TOOLS_DIR=$(CHERILIBSDIR)/tools/
PERIPHERALS_DIR=$(CHERILIBSDIR)/peripherals/
# software for boot rom
MINIBOOT_DIR=../../../../cheribsd/trunk/miniboot/

# define MICRO to build a TLB-less, L2-less CHERI
# MICRO=Yes

# define DIMM=4 to build with timing for a Micron/Crucial 4GB DIMM
# note this just affects timing, not memory size
ifndef DIMM
DIMM=1
endif

# configuration files critical to the design:
QUARTUS_CONFIG=$(QUARTUS_PROJECT).qpf $(wildcard *.sdc)
# Qsys project source
ifdef PCIEXPRESS
QSYS_TEMPLATE=$(QSYS_PROJECT)_pciexpress_template
else
QSYS_TEMPLATE=$(QSYS_PROJECT)_template
endif
QSYS_GENERATED=$(QSYS_PROJECT)
QSYS_PROJECT_SRCS=$(QSYS_PROJECT).qsys

# derived variables
QSYS_GENERATED_FILES=$(QSYS_PROJECT).sopcinfo PLLJ_PLLSPE_INFO.txt DE4_SOC_ddr2_p0_summary.csv $(QSYS_PROJECT_SRCS)
QSYS_SYNTHESIS_DIR=./$(QSYS_PROJECT)/synthesis/
MEGAWIZARD_GENERATED_FILES=pll125.v pll125_bb.v pll125.qif display_pll.v display_pll_bb.v display_pll.qip \
	pll_125_bb.v pll_125.bsf pll_125.ppf pll_125.qip pll_125.v display_pll.ppf

QUARTUS_GENERATED_DIRS=incremental_db db output_files output_files_nodip output_files_default DE4_SOC

.PHONY : all
all :  start_msg check_env temp patch_cheri2 build_cheri build_peripherals build_qsys build_fpga report_critical report_fmax report_error end_msg

.PHONY : start_msg
start_msg:
	@echo "**********************************************************************"
	@echo "* Build started at `date`"
	@echo "**********************************************************************"

.PHONY : end_msg
end_msg:
	@echo "**********************************************************************"
	@echo "* Build ended at `date`"
	@echo "**********************************************************************"

.PHONY : check_env
check_env:
	@(/usr/bin/xdpyinfo > /dev/null || (echo "ERROR: X11 display must be active for this build to complete." ; echo "Use VNC or Xvfb if you aren't on an X-enabled machine" && false))
	@((quartus_map --version | grep 'Version '$(QUARTUS_VERSION)) || ((echo "ERROR: this build has been tested against Quartus "$(QUARTUS_VERSION)" but you have version"; quartus_map --version) && false))

.PHONY : temp
temp:
	mkdir -p $(TEMP)

CHERI_CONFIG_VARS :=
VERILOG_DEFINES :=
ifdef CHERI2
	# be sure to include a debug unit on cheri2 as it is not on by default
	CHERI_CONFIG_VARS += DEBUG=t
endif
ifdef CAP
	CHERI_CONFIG_VARS += CAP=t
endif
ifdef MULTI
	CHERI_CONFIG_VARS += MULTI=$(MULTI)
        ifdef TIMEBASED
		CHERI_CONFIG_VARS += TIMEBASED=t
        endif
endif
ifdef GENERICL1
	CHERI_CONFIG_VARS += GENERICL1=1
endif
ifdef WITH_NOCACHE
	CHERI_CONFIG_VARS += WITH_NOCACHE=t
endif
ifdef MICRO
	CHERI_CONFIG_VARS += MICRO=t
endif
ifdef CHERIOS
	CHERI_CONFIG_VARS += CHERIOS=t
endif
ifdef NOBRANCH
	CHERI_CONFIG_VARS += NOBRANCH=t
endif
ifdef HARDCALL
	CHERI_CONFIG_VARS += HARDCALL=t
endif
ifdef COP1
	CHERI_CONFIG_VARS += COP1=t
endif
ifdef FPU
	CHERI_CONFIG_VARS += COP1=t
endif
ifdef TRACE
	CHERI_CONFIG_VARS += TRACE=t
endif
ifdef PCIEXPRESS
	CHERI_CONFIG_VARS += PCIEXPRESS=t
	VERILOG_DEFINES += --verilog_macro="ENABLE_PCIE=t"
endif
ifdef DMA
	CHERI_CONFIG_VARS += DMA=1
endif
ifdef DMA_VIRT
	CHERI_CONFIG_VARS += DMA_VIRT=1
endif

# Patch files for cheri2 build. Note that we set the timestamps on
# patched files so that we can later detect if they are modified and
# refuse to overwrite.
.PHONY : patch_cheri2
patch_cheri2:
ifdef CHERI2
	@if [ -z "$$(ls | grep '.*original')" ]; then \
	echo "**********************************************************************"; \
	echo "* Patching files for cheri2 build.                                    "; \
	echo "**********************************************************************"; \
	patch -p5 --backup --suffix .original < cheri2.patch; \
	ls | grep '.*original' | while read orig_file; do \
	touch "$$orig_file" "$${orig_file/.original/}" ; \
	done ; \
	else \
	echo "**********************************************************************"; \
	echo "* Detected cheri2 patches already patched.                            "; \
	echo "**********************************************************************"; \
	fi
else
	@true
endif

.PHONY : build_cheri build_beri build_processor

build_processor:	build_cheri

build_beri:	build_cheri

build_cheri:
	@echo "**********************************************************************"
	@echo "* Build Processor Bluespec in " $(CHERI_DIR)
	@echo "**********************************************************************"
	$(MAKE) -C $(CHERI_DIR) verilog $(CHERI_CONFIG_VARS)

.PHONY : build_peripherals
build_peripherals:
	@echo "**********************************************************************"
	@echo "* Build Peripherals in " $(PERIPHERALS_DIR)
	@echo "**********************************************************************"
	$(MAKE) -C $(PERIPHERALS_DIR)

.PHONY : build_miniboot
build_miniboot:
ifdef MICRO
	# Micro CHERI without TLB won't run FreeBSD, so include bare metal code instead
	# of miniboot
	@echo "**********************************************************************"
	@echo "* Build bare metal code ROM (mem64.hex) in " $(CHERI_DIR)/sw
	@echo "**********************************************************************"
	$(MAKE) -C $(CHERI_DIR)/sw verilog
	cp $(CHERI_DIR)/sw/mem64.hex ./
else
	@echo "**********************************************************************"
	@echo "* Build miniboot ROM (mem64.hex) in " $(MINIBOOT_DIR)
	@echo "**********************************************************************"
ifdef CHERIOS
	$(MAKE) -C $(CHERI_DIR) miniboot CHERIOS=cherios
else
	$(MAKE) -C $(CHERI_DIR) miniboot
endif
endif

# Force version.hex to be regenerated for every build.
.PHONY: version.hex
version.hex:
	@echo "**********************************************************************"
	@echo "* Generate version.hex"
	@echo "**********************************************************************"
	tclsh $(TOOLS_DIR)/versionHexGenerate.tcl

ifdef MULTI
DTS_CPP_FLAGS+=	-DMULTI=$(MULTI)
endif
ifdef THREADSZ
DTS_CPP_FLAGS+=	-DTHREADSZ=$(THREADSZ)
endif

$(QUARTUS_PROJECT).dts.cpp: $(QUARTUS_PROJECT).dts.in
	cpp $(DTS_CPP_FLAGS) -x assembler-with-cpp -include $< /dev/null | \
	    grep -v '^# [0-9]* "' > $@

.PHONY: $(QUARTUS_PROJECT).dts
$(QUARTUS_PROJECT).dts: $(QUARTUS_PROJECT).dts.cpp
	@echo "**********************************************************************"
	@echo "* Generate DTS file"
	@echo "**********************************************************************"
	$(TOOLS_DIR)/process-dts.sh $< $@

$(QUARTUS_PROJECT).dtb: $(QUARTUS_PROJECT).dts
	dtc -O dtb -o $@ -b 0 $<

# Intel hex format file of the FDT to include in a ROM
dtb.hex: $(QUARTUS_PROJECT).dtb
	srec_cat -Output $@ -Intel -Output_Block_Size 4 $< -Binary -Byte_Swap 4 -fill=0x00 0x00 0x2000 --address-length=2
	perl -p -i -e '$$line = $$_; $$fmt = sprintf("%04X",$$i); $$line =~ s/\:04....(.*)../\:04$$fmt$$1/; $$_ = $$line; $$i++;' dtb.hex
	perl -p -i -e '$$line = $$_; if ($$line =~ /\:04/) {$$line =~ s/\n//; $$tmp = $$line; $$sum = 0; $$tmp =~ s/([0-9A-F]{2})/$$sum+=hex($$1)/eg; $$sum = (~$$sum & 0xFF) + 1; $$sum = sprintf("%02X",$$sum); $$sum =~ s/.*(..)/$$1/; $$_ = $$line.$$sum."\n";}' dtb.hex

.PHONY : build_qsys
build_qsys: check_env check_bash megawizard $(CHERI_DIR)/ip_name.txt
	@echo "**********************************************************************"
	@echo "* Qsys generation"
	@echo "**********************************************************************"
	#rm $(QSYS_PROJECT).qsys
	# patch the Qsys project with various changes we have to make
	perl fixup_qsys.pl $(DIMM) `cat $(CHERI_DIR)/ip_name.txt` $(QSYS_TEMPLATE).qsys $(QSYS_GENERATED).qsys
ifdef MULTI
	# reduce multicore clock frequency to 80MHz
	sed -i 's/200\.0/180\.180/g' $(QSYS_GENERATED).qsys 
endif
	ip-generate \
	  --report-file=bsf:./output_files/$(QSYS_PROJECT).bsf \
	  --standard-reports \
	  --system-info=DEVICE_FAMILY=$(FPGA) \
	  --output-directory=$(QSYS_SYNTHESIS_DIR) \
	  --project-directory=./ \
	  --file-set=QUARTUS_SYNTH \
	  --component-file=$(QSYS_GENERATED).qsys

.PHONY : check_bash
check_bash:
	@[ -L /bin/sh ] && [ `/bin/readlink /bin/sh` = bash ] && \
	(echo "Info: /bin/sh -> bash") || \
	(echo "**** WARNING /bin/sh isn't a link to bash which may cause Qsys scripts to fail")

.PHONY : build_fpga
.DELETE_ON_ERROR: output_files/$(QSYS_PROJECT_VERSION).sof
build_fpga: dtb.hex version.hex build_miniboot build_qsys build_peripherals
	@echo "**********************************************************************"
	@echo "* Synthesis run started to generate" output_files/$(QUARTUS_PROJECT_VERSION).sof
	@echo "**********************************************************************"
	quartus_map --read_settings_files=on --write_settings_files=off $(QUARTUS_PROJECT) -c $(QUARTUS_PROJECT_VERSION) -l $(BLUESPEC_VERILOG) $(VERILOG_DEFINES)
# REMOVE:  -l $(QSYS_PROJECT)/synthesis -l $(QSYS_PROJECT_SUBMODULES) -l $(BLUESPEC_VERILOG)
	quartus_cdb --read_settings_files=off --write_settings_files=off $(QUARTUS_PROJECT) -c $(QUARTUS_PROJECT_VERSION) --merge=on
	quartus_fit --read_settings_files=off --write_settings_files=off $(QUARTUS_PROJECT) -c $(QUARTUS_PROJECT_VERSION)
	quartus_sta $(QUARTUS_PROJECT) -c $(QUARTUS_PROJECT_VERSION)
	quartus_asm --read_settings_files=off --write_settings_files=off $(QUARTUS_PROJECT) -c $(QUARTUS_PROJECT_VERSION)
	cp $(QSYS_SYNTHESIS_DIR)/*.sopcinfo .

# REMOVE: quartus_sh --flow compile $(QUARTUS_PROJECT_VERSION)

.PHONY : report_fmax
report_fmax:
	@echo "**********************************************************************"
	@echo "* Reporting Fmax summary"
	@echo "**********************************************************************"
	@grep -B3 -A20 "Restricted Fmax" output_files/DE4_BERI.sta.rpt

.PHONY : report_timing_stats
report_timing_stats:
	@echo "**********************************************************************"
	@echo "* Reporting timing stats"
	@echo "**********************************************************************"
	quartus_sta -t $(TOOLS_DIR)/timequest_csv.tcl \
		$(QUARTUS_PROJECT) output_files/fmax.csv output_files/slack.csv \
		output_files/jenkins_fmax.csv output_files/jenkins_slack.csv "DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[4]" 900
	quartus_sta -t $(TOOLS_DIR)/timequest_csv.tcl \
		$(QUARTUS_PROJECT) output_files/fmax.csv output_files/slack.csv \
		output_files/jenkins_mem_fmax.csv output_files/jenkins_mem_slack.csv "DE4_SOC_inst|ddr2|pll0|upll_memphy|auto_generated|pll1|clk[0]" 900

.PHONY : report_critical
report_critical:
	@echo "**********************************************************************"
	@echo "* Reporting Critical Warnings During Synthesis"
	@echo "**********************************************************************"
	@/bin/egrep '^Critical' output_files/*.rpt || echo "No Critical Warnings"

.PHONY : report_error
report_error:
	@echo "**********************************************************************"
	@echo "* Reporting Errors During Synthesis"
	@echo "**********************************************************************"
	@/bin/egrep '^Error' output_files/*.rpt || echo "No Errors"

.PHONY : update_mif
update_mif: _update_mif report_critical report_error

.PHONY : _update_mif
_update_mif: build_miniboot
	quartus_cdb $(QUARTUS_PROJECT) -c $(QUARTUS_PROJECT_VERSION) --update_mif
	quartus_asm --read_settings_files=on --write_settings_files=off $(QUARTUS_PROJECT) -c $(QUARTUS_PROJECT_VERSION)
	cp $(QSYS_SYNTHESIS_DIR)/*.sopcinfo .

.PHONY:	megawizard
megawizard:
	@echo "**********************************************************************"
	@echo "* Build local PLLs"
	@echo "**********************************************************************"
	cp pll_125.v.template pll_125.v
	qmegawiz -silent pll_125.v
	cp display_pll.v.template display_pll.v
	qmegawiz -silent display_pll.v
	cp altgx_reconfig.v.template altgx_reconfig.v
	qmegawiz -silent altgx_reconfig.v

.PHONY : build_nodip_wait
build_nodip_wait: _always_nodip_msg _always_nodip update_mif _always_nodip_restore_dir

.PHONY : _always_nodip_restore_dir
_always_nodip_restore_dir:
	# Make sure the default bitfile stays in the expected output dir.
	mv output_files output_files_nodip
	mv output_files_default output_files
	# Also restore intial.hex.
	mv mem64.hex mem64-nodip.hex
	mv mem64-default.hex mem64.hex

.PHONY : _always_nodip_msg
_always_nodip_msg:
	@echo "**********************************************************************"
	@echo "* Rebuilding bitfile with miniboot ingoring DIP switch for waiting"
	@echo "**********************************************************************"

.PHONY : _always_nodip
_always_nodip: build_fpga
	# Swap miniboot ROMs.
	mv mem64.hex mem64-default.hex
	mv mem64-nodip.hex mem64.hex
	# Save previously built files.
	cp -pr output_files output_files_default

.PHONY : download
download :
	@echo "**********************************************************************"
	@echo "* Downloading the FPGA image to the FPGA "
	@echo "**********************************************************************"
	@echo "* If this fails you may need to check if the FPGA can be seen using: "
	@echo "*   jtagconfig "
	@echo "* to see what devices are present.  If this still doesn't work, "
	@echo "* fire up the Quartus IDE and use the graphical programming tool "
	@echo "* to diagnose the problem and create a new programming chain "
	@echo "* ("$(QUARTUS_PROJECT_VERSION)".cdf) file. "
	@echo "**********************************************************************"
	quartus_pgm $(QUARTUS_PROJECT_VERSION).cdf
	@echo "**********************************************************************"
	@echo "* Download of hardware ("$(QUARTUS_PROJECT_VERSION).sof") complete"
	@echo "**********************************************************************"

.PHONY: restore_originals
restore_originals:
	@echo "**********************************************************************"
	@echo "* Restoring cheri2 patched files to originals."
	@echo "**********************************************************************"
	@ls *.original 2>/dev/null | while read orig_file; do \
	orig_name="$${orig_file/.original/}" ; \
	if [ "$$orig_name" -nt "$$orig_file" -a -z "${FORCE}" ]; then \
	echo "REFUSING TO OVERWRITE MODIFIED FILE $$orig_name" ; \
	echo "Set FORCE=1 or do this manually using 'mv $$orig_file $$orig_name'." ; \
	exit 1; \
	else \
	echo "Restoring original $$orig_name from $$orig_file" ; \
	mv "$$orig_file" "$$orig_name"; \
	fi; done

.PHONY : cleanq
cleanq:
	rm -f  $(QSYS_GENERATED_FILES)
	rm -rf $(QSYS_SYNTHESIS_DIR)
	rm -rf $(QUARTUS_GENERATED_DIRS)
	rm -f  dtb.hex $(QUARTUS_PROJECT).dtb
	rm -f  $(QUARTUS_PROJECT).dts $(QUARTUS_PROJECT).dts.cpp
	rm -f  mem64.hex mem64-default.hex mem64-nodip.hex version.hex
	rm -rf greybox_tmp
	rm -f  $(MEGAWIZARD_GENERATED_FILES)	

.PHONY : cleanall
cleanall: cleanq restore_originals
	$(MAKE) -C $(CHERI_DIR) clean
	$(MAKE) -C $(PERIPHERALS_DIR) clean
	$(MAKE) -C $(MINIBOOT_DIR) clean

.PHONY : clean
clean: cleanq
	@echo "WARNING: this did not clean CHERI, peripherals or miniboot"
	@echo "         use 'make cleanall' to clean CHERI, peripherals and miniboot"

.PHONY : help
help :
	@echo "Summary of makefile targets"
	@echo "               all - builds everything using the following steps (except download)"
	@echo "   build_processor - CHERI/BERI processor"
	@echo " build_peripherals - peripherals"
	@echo "    build_miniboot - build miniboot ROM and copy mem64.hex here"
	@echo "        build_qsys - build Qsys project containing CHERI, etc."
	@echo "        build_fpga - synthesis, map, fit, timing analyse and generate FPGA image"
	@echo "  build_nodip_wait - build_fpga with modified miniboot to ignore wait DIP switch"
	@echo "       report_fmax - extracts the Fmax summary from build_fpga reports"
	@echo "report_timing_stats- output important timing info as CSV files"
	@echo "   report_critical - scans build_fpga reports for critical warnings"
	@echo "      report_error - scans build_fpga reports for errors"
	@echo "        update_mif - Update memory intialization files"
	@echo "          download - attempts to download the FPGA (.sof) image to the FPGA"
	@echo "                     but the chain file (.cdf) may need to be updated for"
	@echo "                     your configuration (e.g. USB port number)"
	@echo "             clean - remove Quartus and Qsys build files"
	@echo "          cleanall - clean + clean peripherals, CHERI and miniboot"
