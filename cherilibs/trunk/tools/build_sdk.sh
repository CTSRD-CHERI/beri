#!/bin/sh
#-
# Copyright (c) 2013 David T. Chisnall
# Copyright (c) 2013 Jonathan Woodruff
# Copyright (c) 2013-2014 Jonathan Anderson
# Copyright (c) 2013-2017 SRI International
# Copyright (c) 2016 A. Theodore Markettos
# Copyright (c) 2016 Alexandre Joannou
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

SDK_VERSION=3

check_dep()
{
	if [ -z "$(which "$1")" ] ; then
		echo "error: No $1 binary found in PATH: ${PATH}"
		echo "$2"
		FOUNDDEPS=0
	else
		echo "-- Found $1..."
	fi
}
try_to_run()
{
	if [ -z "${VERBOSE}" ] ; then
		"$@" > "${WD}/error.log" 2>&1
	else
		"$@" 2>&1 | tee "${WD}/error.log"
	fi
	if [ $? -ne 0 ] ; then
		echo "$1 failed, see error.log for details"
		echo "Full command: $@"
		exit 1
	fi
}
FOUNDDEPS=1
echo Checking dependencies...
check_dep cmake "Required for building LLVM"
check_dep ninja "Required for building LLVM"
check_dep clang++37 "Required for building LLVM"
check_dep git "Required for fetching source code"
WD=$(realpath .)
if [ -z "${MAKEOBJDIRPREFIX}" ] ; then
	printf %s "MAKEOBJDIRPREFIX is not set, use current location? (lots of object code will go there!) [y/N] "
	read -r yn
	if [ "$yn" = y ] ; then
		mkdir obj
		export MAKEOBJDIRPREFIX=${WD}/obj
	else
		echo MAKEOBJDIRPREFIX must be set to a where you want to build FreeBSD
		FOUNDDEPS=0
	fi
fi
if [ -z "${JFLAG}" ] ; then
	JFLAG=$(sysctl kern.smp.cpus | awk '{ printf "-j" $2 }')
	echo "No JFLAG specified, defaulting to ${JFLAG}"
fi
if [ ${FOUNDDEPS} = 0 ] ; then
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

if [ -f "$SDKROOT_DIR/version" ] ; then
	EXISTING_SDK_VERSION=$(cat "$SDKROOT_DIR/version")
else
	EXISTING_SDK_VERSION=0
fi

# If we're building a new version of the SDK, delete the old one
if [ $EXISTING_SDK_VERSION -ne $SDK_VERSION ] ; then
	echo Deleting old SDK if one exists...
	rm -rf "$SDKROOT_DIR"
	mkdir -p "$SYSROOT_DIR"
fi

#
# Choice of hard- vs soft-float is cached in .hardfloat.
#

if [ -e .hardfloat ]; then
	yn="$(cat .hardfloat)"
fi

if [ "$yn" = y ] ; then
	echo "There is currently no support for hard-float MIPS."
	echo "Remove ./.hardfloat to continue."
else
	echo "Will build SDK for soft-float MIPS"
fi

if [ -e .chericapwidth ]; then
	bitwidth=`cat .chericapwidth`
else
	echo "Enter CHERI capability bit width (blank for 256, 128 also supported)"
	read -r bitwidth
fi
if [ "${bitwidth}" != 128 ]; then
	bitwidth=256
fi
echo -n ${bitwidth} > .chericapwidth
echo Building ${bitwidth}-bit CHERI SDK

if [ -d llvm ] ; then
	echo Updating CHERI-LLVM...
	cd llvm || exit 1
	DIFF=$(git diff | wc -l)
	if [ "$DIFF" -ne 0 ] ; then
		try_to_run git stash
	fi
	try_to_run git pull --rebase
	if [ "$DIFF" -ne 0 ] ; then
		try_to_run git stash pop
	fi
	cd tools || exit 1
else
	echo Fetching CHERI-LLVM...
	try_to_run git clone http://github.com/CTSRD-CHERI/llvm
	cd llvm/tools || exit 1
	if [ "x$NEWISA" != "x" ] ; then
		echo "Using 'newisa' branch of LLVM"
		try_to_run git checkout newisa
	fi
fi
if [ -d clang ] ; then
	echo Updating CHERI-Clang...
	cd clang || exit 1
	DIFF=$(git diff | wc -l)
	if [ "$DIFF" -ne 0 ] ; then
		try_to_run git stash
	fi
	try_to_run git pull --rebase
	if [ "$DIFF" -ne 0 ] ; then
		try_to_run git stash pop
	fi
	cd .. || exit 1
else
	echo Fetching CHERI-Clang...
	try_to_run git clone https://github.com/CTSRD-CHERI/clang
fi
if [ -d lld ] ; then
	echo Updating CHERI-LLD...
	cd lld || exit 1
	DIFF=$(git diff | wc -l)
	if [ "$DIFF" -ne 0 ] ; then
		try_to_run git stash
	fi
	try_to_run git pull --rebase
	if [ "$DIFF" -ne 0 ] ; then
		try_to_run git stash pop
	fi
	cd .. || exit 1
else
	echo Fetching CHERI-LLD...
	try_to_run git clone https://github.com/CTSRD-CHERI/lld
fi
cd ..

# If we've got an older version of the SDK, then delete the LLVM build dir and
# reconfigure it for the new location.
if [ $EXISTING_SDK_VERSION -lt ${SDK_VERSION} ] ; then
	echo Removing old LLVM build directory...
	rm -rf Build
fi

if [ -d Build ] ; then
	cd Build
else
	mkdir Build
	cd Build
	echo Configuring LLVM Build...
	CAPWIDTHFLAG=
	if [ ${bitwidth} -eq 128 ]; then
		CAPWIDTHFLAG=-DLLVM_CHERI_IS_128=ON
	fi
	try_to_run cmake .. -DCMAKE_CXX_COMPILER=clang++37 -DCMAKE_C_COMPILER=clang -DCMAKE_BUILD_TYPE=Release "-DDEFAULT_SYSROOT=${SYSROOT_DIR}" -DLLVM_DEFAULT_TARGET_TRIPLE=cheri-unknown-freebsd "-DCMAKE_INSTALL_PREFIX=${SDKROOT_DIR}" ${CAPWIDTHFLAG} -G Ninja
fi
echo Building LLVM...
try_to_run ninja "${JFLAG}"
echo Installing LLVM...
try_to_run ninja install
cd ../.. || exit 1
# delete some things that we don't need...
rm -rf "${SDKROOT_DIR}"/lib/lib*
rm -rf "${SDKROOT_DIR}"/share
rm -f "${SDKROOT_DIR}"/lib/clang/[123456789].*/include/std*
rm -f "${SDKROOT_DIR}"/lib/clang/[123456789].*/include/limits.h
CHERIBSD_ROOT=$(realpath .)/cheribsd
if [ -d cheribsd ] ; then
	echo Updating CheriBSD...
	cd cheribsd || exit 1
	DIFF=$(git diff | wc -l)
	if [ "$DIFF" -ne 0 ] ; then
		try_to_run git stash
	fi
	try_to_run git pull --rebase
	if [ "$DIFF" -ne 0 ] ; then
		try_to_run git stash pop
	fi
	cd ..
else
	echo Fetching CheriBSD...
	try_to_run git clone https://github.com/CTSRD-CHERI/cheribsd
fi

cd "${CHERIBSD_ROOT}" || exit 1

if [ "x$NEWISA" != "x" ] ; then
	echo "Using 'newisa' branch of CheriBSD"
	try_to_run git checkout newisa
fi

echo Building the toolchain...
# The lack of '/' in "mips.mips64`realpath .`" is critical to installworld,
# don't change.
CHERIROOT_OBJ="${MAKEOBJDIRPREFIX}/mips.mips64$(realpath .)/tmproot"
CHERITOOLS_OBJ="${MAKEOBJDIRPREFIX}/mips.mips64$(realpath .)/tmp/usr/bin/"
CHERIBOOTSTRAPTOOLS_OBJ="${MAKEOBJDIRPREFIX}/mips.mips64$(realpath .)/tmp/legacy/usr/bin/"
CHERILIBEXEC_OBJ="${MAKEOBJDIRPREFIX}/mips.mips64$(realpath .)/tmp/usr/libexec/"

echo Building FreeBSD base distribution...
echo "NO_BUILDWORLD value: ${NO_BUILDWORLD}"

# The only way to have a array variable in POSIX sh seems to be using set inside a function
build_freebsd() {
	#set -- CHERI=256 "CHERI_CC=${SDKROOT_DIR}/bin/clang" -DDB_FROM_SRC -DNO_ROOT -DNO_WERROR -DNO_CLEAN
	set -- CHERI=${bitwidth} "CHERI_CC=${SDKROOT_DIR}/bin/clang" -DDB_FROM_SRC -DNO_ROOT -DNO_WERROR
    if [ "x$JEMALLOC" != "x" ] ; then
	    echo "Building with JEMALLOC"
	    set -- CHERI=${bitwidth} "CHERI_CC=${SDKROOT_DIR}/bin/clang" -DDB_FROM_SRC -DNO_ROOT -DNO_WERROR -DWITH_LIBCHERI_JEMALLOC
    fi
	echo make "${JFLAG}" "$@" buildworld
	# Do a non-parallel cleandir to work around build system bugs.
	try_to_run make "$@" cleandir
	try_to_run make "${JFLAG}" "$@" buildworld
	echo "Installing FreeBSD base distribution to ${CHERIROOT_OBJ}..."
	rm -rf "${CHERIROOT_OBJ}"
	mkdir -p "${CHERIROOT_OBJ}"
	try_to_run make "${JFLAG}" "$@" DESTDIR="${CHERIROOT_OBJ}" installworld
}

if [ -z "${NO_BUILDWORLD}" ]; then
	rm -f ${SDKROOT_DIR}/bin/ld
	rm -f ${SDKROOT_DIR}/bin/*-ld
	build_freebsd
fi
echo Populating SDK...
cd "${SYSROOT_DIR}" || exit 1
(cd "${CHERIROOT_OBJ}" && tar cf - --include="./lib/" --include="./usr/include/" --include="./usr/lib/" --include="./usr/libcheri" --include="./usr/libdata/" @METALOG) | tar xf -
if [ $? -ne 0 ] ; then
	exit 1
fi
echo Installing tools...
mkdir -p "${SDKROOT_DIR}/bin"
TOOLS="as objdump strings addr2line gcc gcov nm strip ld objcopy size brandelf"
for TOOL in ${TOOLS} ; do
	if [ -r "${CHERITOOLS_OBJ}/${TOOL}" ]; then
		cp -f "${CHERITOOLS_OBJ}/${TOOL}" "${SDKROOT_DIR}/bin/${TOOL}"
	elif [ -r "${CHERIBOOTSTRAPTOOLS_OBJ}/${TOOL}" ]; then 
		cp -f "${CHERIBOOTSTRAPTOOLS_OBJ}/${TOOL}" "${SDKROOT_DIR}/bin/${TOOL}"
	else
		echo "Can't find ${TOOL}"
	fi
done
# GCC wants the cc1 and cc1plus tools to be in the directory specified by -B.
# We must make this the same directory that contains ld for linking and
# compiling to both work...
for TOOL in cc1 cc1plus ; do
	cp -f "${CHERILIBEXEC_OBJ}/${TOOL}" "${SDKROOT_DIR}/bin/${TOOL}"
done
cd "${SDKROOT_DIR}/bin" || exit 1
TOOLS="${TOOLS} clang clang++ llvm-mc llvm-objdump llvm-readobj llvm-size llc lld ld.lld"
for TOOL in ${TOOLS} ; do
	ln -fs "$TOOL" "cheri-unknown-freebsd-${TOOL}"
	ln -fs "$TOOL" "mips4-unknown-freebsd-${TOOL}"
	ln -fs "$TOOL" "mips64-unknown-freebsd-${TOOL}"
done
echo Fixing absolute paths in symbolic links inside lib directory...
echo | cat | cc -x c - -o "${SDKROOT_DIR}/bin/fixlinks" <<EOF
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
cd "${SYSROOT_DIR}/usr/lib" || exit 1
try_to_run "${SDKROOT_DIR}/bin/fixlinks"
echo Compiling cheridis helper...
echo | cat | cc -DLLVM_PATH="\"${SDKROOT_DIR}/bin/\"" -x c - -o "${SDKROOT_DIR}/bin/cheridis" <<EOF
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
echo "$SDK_VERSION" > "$SDKROOT_DIR/version"
echo "Done.  Use ${SDKROOT_DIR}/bin/clang to compile code."
echo "Add --sysroot=${SYSROOT_DIR} -B${SDKROOT_DIR}bin to your CFLAGS"
rm -f error.log
