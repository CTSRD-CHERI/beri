#-
# Copyright (c) 2013 Colin Rothwell
# All rights reserved.
#
# This software was developed by Colin Rothwell as part of his final year
# undergraduate project.
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
BSC=bsc
SHARED_SRCS=../megafunctions/*.bsv
# Include CoProcessor, Cheri and Megafunctions
BSV_PATH=+:../..:../../bsim:..:../megafunctions:../../../../cherilibs/trunk
BSV_PATH:=$(BSV_PATH):%/Libraries/Contrib/NonPipelinedMath
BSCFLAGS=-keep-fires -cross-info -aggressive-conditions -p $(BSV_PATH)
BSCFLAGS+=-bdir bsim -simdir bsim -u #+RTS -K4GB -RTS
SIMFLAGS=-sim -D BLUESIM
VERILOGFLAGS=-vdir verilog -verilog

ifdef MEGAFUNCTIONS
	BSCFLAGS+=-D MEGAFUNCTIONS
endif

BUILDSIM = $(BSC) $(BSCFLAGS) $(SIMFLAGS) $(1) &&\
		   $(BSC) $(BSCFLAGS) $(SIMFLAGS) -l mpfr -l gmp -e $(2) -o simulation/$(2)

BUILDVERILOG=$(BSC) $(BSCFLAGS) $(VERILOGFLAGS) -o verilog/$@ $<

#TODO: Add a "make all" rule.

bsim/%.bo: %.bsv
	$(BSC) $(BSCFLAGS) $<

simulation/mkInstantiateCoPro:
	$(call BUILDSIM,InstantiateCoPro.bsv,mkInstantiateCoPro)

simulation/mkCompositeOpTests: 
	$(call BUILDSIM,CompositeOpTests.bsv,mkCompositeOpTests)

simulation/mkDiadicMegafunctionSimulationTests:
	$(call BUILDSIM,DiadicMegafunctionSimulationTests.bsv,mkDiadicMegafunctionSimulationTests)

simulation/mkFloatingPointConversionTest:
	$(call BUILDSIM,FloatingPointConversionTest.bsv,mkFloatingPointConversionTest)

simulation/mkMegafunctionServerTests: MegafunctionServerTests.bsv
	$(call BUILDSIM,MegafunctionServerTests.bsv,mkMegafunctionServerTests)

verilog/mkMegafunctionServerTests.v: MegafunctionServerTests.bsv
	$(call BUILDVERILOG,mkMegafunctionServerTests)

simulation/mkMonadicMegafunctionTests:
	$(call BUILDSIM,MonadicMegafunctionTests.bsv,mkMonadicMegafunctionTests)

simulation/mkDiadicMegafunctionWrapperTestBench:
	$(call BUILDSIM,TestDiadicMegafunctionWrapper.bsv,mkDiadicMegafunctionWrapperTestBench)

simulation/mkConversionTests: ConversionTests.bsv
	$(call BUILDSIM,ConversionTests.bsv,mkConversionTests)

simulation/mkDivTests: DivTests.bsv
	$(call BUILDSIM,DivTests.bsv,mkDivTests)

.PHONY: clean
clean:
	rm -rf bsim/* simulation/*
