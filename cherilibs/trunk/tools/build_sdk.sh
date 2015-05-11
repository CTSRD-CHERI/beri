#!/bin/sh
#-
# Copyright (c) 2013 David T. Chisnall
# Copyright (c) 2013 Jonathan Woodruff
# Copyright (c) 2013-2014 Jonathan Anderson
# Copyright (c) 2013-2014 SRI International
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

SDK_VERSION=1

check_dep()
{
	if [ -z "`which $1`" ] ; then
		echo error: No $1 binary found in PATH: ${PATH}
		echo $2
		FOUNDDEPS=0
	else
		echo -- Found $1...
	fi
}
try_to_run()
{
	$@ > ${WD}/error.log 2>&1
	if [ $? -ne 0 ] ; then
		echo $1 failed, see error.log for details
		exit 1
	fi
}
FOUNDDEPS=1
echo Checking dependencies...
check_dep cmake "Required for building LLVM"
check_dep ninja "Required for building LLVM"
check_dep clang++ "Required for building LLVM"
check_dep git "Required for fetching source code"
WD=`realpath .`
if [ -z "${MAKEOBJDIRPREFIX}" ] ; then
	echo "MAKEOBJDIRPREFIX is not set, use current location? (lots of object code will go there!)"
	read yn
	if [ "$yn" == y ] ; then
		mkdir obj
		export MAKEOBJDIRPREFIX=${WD}/obj
	else
		echo MAKEOBJDIRPREFIX must be set to a where you want to build FreeBSD
		FOUNDDEPS=0
	fi
fi
if [ -z "${JFLAG}" ] ; then
	JFLAG=`sysctl kern.smp.cpus | awk '{ printf "-j" $2 }'`
	echo No JFLAG specified, defaulting to ${JFLAG}
fi
if [ ${FOUNDDEPS} == 0 ] ; then
	exit 1
fi
echo All dependencies satisfied
if [ ! -d sdk ] ; then
	mkdir sdk
fi
if [ ! -d sdk/sysroot ] ; then
	mkdir sdk/sysroot
fi
SDKROOT_DIR=${WD}/sdk/
SYSROOT_DIR=${SDKROOT_DIR}sysroot/
CPUTYPE=mips

if [ -f $SDKROOT_DIR/version ] ; then
	EXISTING_SDK_VERSION=`cat $SDKROOT_DIR/version`
else
	EXISTING_SDK_VERSION=0
fi

# If we're building a new version of the SDK, delete the old one
if [ $EXISTING_SDK_VERSION -ne $SDK_VERSION ] ; then
	echo Deleting old SDK if one exists...
	rm -rf $SDKROOT_DIR
	mkdir -p $SYSROOT_DIR
fi

#
# Choice of hard- vs soft-float is cached in .hardfloat.
#

if [ -e .hardfloat ]; then
	yn="`cat .hardfloat`"
else
	echo 
	echo "Would you like a hard-float SDK?"
	read yn
	echo $yn > .hardfloat
fi

if [ "$yn" == y ] ; then
	echo "Will build SDK for hard-float MIPS"
	CPUTYPE=mipsfpu
else
	echo "Will build SDK for soft-float MIPS"
fi

if [ -d llvm ] ; then
	echo Updating CHERI-LLVM...
	cd llvm
	DIFF=`git diff | wc -l`
	if [ $DIFF -ne 0 ] ; then
		try_to_run git stash
	fi
	try_to_run git pull --rebase
	if [ $DIFF -ne 0 ] ; then
		try_to_run git stash pop
	fi
	cd tools
else
	echo Fetching CHERI-LLVM...
	try_to_run git clone http://github.com/CTSRD-CHERI/llvm
	cd llvm/tools
fi
if [ -d clang ] ; then
	echo Updating CHERI-Clang...
	cd clang
	DIFF=`git diff | wc -l`
	if [ $DIFF -ne 0 ] ; then
		try_to_run git stash
	fi
	try_to_run git pull --rebase
	if [ $DIFF -ne 0 ] ; then
		try_to_run git stash pop
	fi
	cd ..
else
	echo Fetching CHERI-Clang...
	try_to_run git clone https://github.com/CTSRD-CHERI/clang
fi
cd ..

# If we've got an older version of the SDK, then delete the LLVM build dir and
# reconfigure it for the new location.
if [ $EXISTING_SDK_VERSION -eq 0 ] ; then
	echo Removing old LLVM build directory...
	rm -rf Build
fi

if [ -d Build ] ; then
	cd Build
else
	mkdir Build
	cd Build
	echo Configuring LLVM Build...
	try_to_run cmake .. -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang -DCMAKE_BUILD_TYPE=Release -DDEFAULT_SYSROOT=${SYSROOT_DIR} -DLLVM_DEFAULT_TARGET_TRIPLE=cheri-unknown-freebsd -DCMAKE_INSTALL_PREFIX=${SDKROOT_DIR} -G Ninja
fi
echo Building LLVM...
try_to_run ninja
echo Installing LLVM...
try_to_run ninja install
cd ../..
# delete some things that we don't need...
rm -rf ${SDKROOT_DIR}/lib/lib*
rm -rf ${SDKROOT_DIR}/share
rm -rf ${SDKROOT_DIR}/include
rm -f ${SDKROOT_DIR}/lib/clang/3.*/include/std*
CHERIBSD_ROOT=`realpath .`/cheribsd
if [ -d cheribsd ] ; then
	echo Updating CheriBSD...
	cd cheribsd 
	DIFF=`git diff | wc -l`
	if [ $DIFF -ne 0 ] ; then
		try_to_run git stash
	fi
	try_to_run git pull --rebase
	if [ $DIFF -ne 0 ] ; then
		try_to_run git stash pop
	fi
	cd ..
else
	echo Fetching CheriBSD...
	try_to_run git clone https://github.com/CTSRD-CHERI/cheribsd
fi
cd ${CHERIBSD_ROOT}
echo Building the toolchain...
# The lack of '/' in "mips.mips64`realpath .`" is critical to installworld,
# don't change.
CHERIROOT_OBJ="${MAKEOBJDIRPREFIX}/mips.mips64`realpath .`/tmproot"
CHERITOOLS_OBJ="${MAKEOBJDIRPREFIX}/mips.mips64`realpath .`/tmp/usr/bin/"
CHERILIBEXEC_OBJ="${MAKEOBJDIRPREFIX}/mips.mips64`realpath .`/tmp/usr/libexec/"
FBSD_BUILD_ARGS="-DCHERI CPUTYPE=${CPUTYPE} CHERI_CC=${SDKROOT_DIR}/bin/clang -DDB_FROM_SRC -DNO_ROOT -DNO_WERROR"
echo Building FreeBSD base distribution...
echo NO_BUILDWORLD value: ${NO_BUILDWORLD}
if [ -z "${NO_BUILDWORLD}" ]; then
	echo make ${JFLAG} ${FBSD_BUILD_ARGS} buildworld
	# Do a non-parallel cleandir to work around build system bugs.
	try_to_run make ${FBSD_BUILD_ARGS} cleandir
	try_to_run make ${JFLAG} ${FBSD_BUILD_ARGS} buildworld
	echo Installing FreeBSD base distribution to ${CHERIROOT_OBJ}...
	rm -rf "${CHERIROOT_OBJ}"
	mkdir -p "${CHERIROOT_OBJ}"
	try_to_run make ${JFLAG} ${FBSD_BUILD_ARGS} DESTDIR="${CHERIROOT_OBJ}" installworld
fi
echo Populating SDK...
cd ${SYSROOT_DIR}
(cd "${CHERIROOT_OBJ}" && tar cf - --include="./lib/" --include="./usr/include/" --include="./usr/lib/" --include="./usr/libdata/" @METALOG) | tar xf -
if [ $? -ne 0 ] ; then
	exit 1
fi
echo Installing tools...
mkdir -p ${SDKROOT_DIR}/bin
TOOLS="as lint objdump strings addr2line c++filt crunchide gcc gcov nm readelf strip ld objcopy size"
for TOOL in ${TOOLS} ; do
	cp -f ${CHERITOOLS_OBJ}/${TOOL} ${SDKROOT_DIR}/bin/${TOOL}
done
# GCC wants the cc1 and cc1plus tools to be in the directory specified by -B.
# We must make this the same directory that contains ld for linking and
# compiling to both work...
for TOOL in cc1 cc1plus ; do
	cp -f ${CHERILIBEXEC_OBJ}/${TOOL} ${SDKROOT_DIR}/bin/${TOOL}
done
cd ${SDKROOT_DIR}/bin
TOOLS="${TOOLS} clang clang++ llvm-mc llvm-objdump llvm-readobj llvm-size llc"
for TOOL in ${TOOLS} ; do
	ln -fs $TOOL cheri-unknown-freebsd-${TOOL}
	ln -fs $TOOL mips4-unknown-freebsd-${TOOL}
	ln -fs $TOOL mips64-unknown-freebsd-${TOOL}
done
echo Fixing absolute paths in symbolic links inside lib directory...
echo | cat | cc -x c - -o ${SDKROOT_DIR}/bin/fixlinks <<EOF
#include <sys/types.h>
#include <sys/stat.h>
#include <dirent.h>
#include <err.h>
#include <errno.h>
#include <stdio.h>
#include <sysexits.h>
#include <unistd.h>
#include <stdlib.h>

int main(int argc, char **argv)
{
	DIR *dir = opendir(".");
	struct dirent *file;
	char *dirname;
	int links = 0, fixed = 0;

	while ((file = readdir(dir)) != NULL)
	{
		char target[1024];
		ssize_t index =
			readlink(file->d_name, target, sizeof(target) - 1);

		if (index < 0) {
			// Not a symlink?
			if (errno == EINVAL)
				continue;

			err(EX_OSERR, "error in readlink('%s')", file->d_name);
		}

		links++;

		// Fix absolute paths.
		if (target[0] == '/') {
			target[index] = 0;

			char *newName;
			asprintf(&newName, "../..%s", target);

			if (unlink(file->d_name))
				err(EX_OSERR, "Failed to remove old link");

			if (symlink(newName, file->d_name))
				err(EX_OSERR, "Failed to create link");

			free(newName);
			fixed++;
		}
	}
	closedir(dir);

	if (links == 0)
		errx(EX_USAGE, "no symbolic links in %s", getwd(NULL));

	printf("fixed %d/%d symbolic links\n", fixed, links);
}
EOF
cd ${SYSROOT_DIR}/usr/lib
try_to_run ${SDKROOT_DIR}/bin/fixlinks 
echo Compiling cheridis helper...
echo | cat | cc -DLLVM_PATH=\"${SDKROOT_DIR}/bin/\" -x c - -o ${SDKROOT_DIR}/bin/cheridis <<EOF
#include <stdio.h>
#include <string.h>

int main(int argc, char** argv)
{
	int i;
	int byte;

	FILE *dis = popen(LLVM_PATH "llvm-mc -disassemble -triple=cheri-unknown-freebsd", "w");
	for (i=1 ; i<argc ; i++)
	{
		char *inst = argv[i];
		if (strlen(inst) == 10)
		{
			if (inst[0] != '0' || inst[1] != 'x') continue;
			inst += 2;
		}
		else if (strlen(inst) != 8) continue;
		for (byte=0 ; byte<8 ; byte+=2)
		{
			fprintf(dis, "0x%.2s ", &inst[byte]);
		}
	}
	pclose(dis);
}
EOF
echo $SDK_VERSION > $SDKROOT_DIR/version
echo Done.  Use ${SDKROOT_DIR}/bin/clang to compile code.
echo Add --sysroot=${SYSROOT_DIR} -B${SDKROOT_DIR}bin to your CFLAGS
rm -f error.log
