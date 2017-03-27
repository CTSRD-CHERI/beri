#-
# Copyright (c) 2013-2016 SRI International
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $Id$
#
# Embedded image creation.  User-driven targets are:
#
# world		- Populate/update world directories
# images	- File system images to embed in kernels
# kernels	- Kernels
# sdcard	- SD Card root file system images
# flash		- Create flash preparation images
# dated		- Create datestamped versions of the above
# clean		- Remove undatestampled files
# clean-dated	- Remove datestampled files
# clean-kernels	- Remove kernel build directories (forces kernel rebuild)
# real-clean	- Remove all of the above plus installed root directories
#
# Make command line options:
# ROOTDIR	DESTDIR of installworld+distribution+installkernel
# SRCDIR	path to the source tree
# DATESTAMP	Prefix of files for publication
# BASE_ABI	ABI for most programs, one of: n64, cheriabi, cheriabi_static
#

MAKEROOT?=	${.CURDIR}/makeroot.sh -B big
DEMO_DIR?=	${.CURDIR}/demo
EXTRAS_DIR?=	${.CURDIR}/extras
KEY_DIR?=	${.CURDIR}/keys
BASE_ABI=?	n64

.sinclude "Makefile.conf"

.if !defined(DATESTAMP)
DATESTAMP!=	date +%Y%m%d
.endif

EXTRAS_demo=	${EXTRAS_DIR}/autosd.mtree ${EXTRAS_DIR}/mdroot.mtree ${DEMO_DIR}/demo.mtree
FILES_demo=	${.CURDIR}/demo.files
SIZE_demo=	26112k

EXTRAS_net=	${EXTRAS_DIR}/sdroot.mtree
FILES_net=	${.CURDIR}/net.files
SIZE_net=	26112k
EXTRAS_sdcard=	${EXTRAS_DIR}/sdroot.mtree ${DEMO_DIR}/demo.mtree ${EXTRAS_DIR}/pkg-cache.mtree
SIZE_sdcard=	1900m
EXCLUDE_sdcard=	/usr/lib/debug|.debug|.dump

EXTRAS_full=	${EXTRAS_sdcard} ${PRODUCT}-pkg-repo.mtree
SIZE_full=	5000m
INODES_full=	10000
BOOTSTRAP_KERNEL_full=	${QEMU_KERNEL}

EXTRAS_smoketest=	${EXTRAS_DIR}/smoketest.mtree
FILES_smoketest=	${.CURDIR}/smoketest.files

EXTRAS_smoketest_bootonly=	${EXTRAS_DIR}/smoketest-bootonly.mtree
FILES_smoketest_bootonly=	${.CURDIR}/smoketest.files

EXTRAS_isca=	${EXTRAS_DIR}/isca.mtree ${DEMO_DIR}/demo.mtree
SIZE_isca=	1200m

SIZE_singleuser=	26112k
FILES_singleuser=	${.CURDIR}/singleuser.files

BERI_KERNELS=	BERI_DE4_2CORE_MDROOT BERI_DE4_2THREAD_MDROOT \
		BERI_DE4_MDROOT BERI_DE4_USBROOT BERI_SIM_MDROOT \
		BERI_DE4_SDROOT \
		MALTA64 \
		BERI_SIM_2CORE_MDROOT BERI_SIM_2THREAD_MDROOT \
		BERI_SOCKIT_MDROOT 
CHERI256_KERNELS=	CHERI_DE4_2CORE_MDROOT CHERI_DE4_2THREAD_MDROOT \
		CHERI_DE4_MDROOT CHERI_DE4_SDROOT CHERI_DE4_NFSROOT CHERI_DE4_USBROOT \
		CHERI_MALTA64 \
		CHERI_SIM_MDROOT \
		CHERI_SIM_2CORE_MDROOT CHERI_SIM_2THREAD_MDROOT \
		CHERI_SOCKIT_MDROOT
CHERI128_KERNELS=	CHERI128_SIM_MDROOT \
		CHERI128_DE4_MDROOT CHERI128_DE4_SDROOT \
		CHERI128_DE4_NFSROOT CHERI128_DE4_USBROOT \
		CHERI128_MALTA64

.if ${BASE_ABI} != "cheriabi_static"
IMAGES=	full net isca sdcard singleuser smoketest smoketest_bootonly
.else
IMAGES=	full smoketest smoketest_bootonly
CHERI256_KERNELS:=	${CHERI256_KERNELS:N*MDROOT}
CHERI128_KERNELS:=	${CHERI128_KERNELS:N*MDROOT}
SIZE_full:=	9500m
.endif

BERI_DE4_2CORE_MDROOT_IMAGES=	singleuser
BERI_DE4_2THREAD_MDROOT_IMAGES=	singleuser
BERI_SIM_MDROOT_IMAGES=		singleuser smoketest smoketest_bootonly
BERI_SIM_2CORE_MDROOT_IMAGES=	singleuser
BERI_SIM_2THREAD_MDROOT_IMAGES=	singleuser
BERI_SOCKIT_MDROOT_IMAGES=	net singleuser
BERI_DE4_MDROOT_IMAGES=		net singleuser smoketest_bootonly
CHERI_DE4_2CORE_MDROOT_IMAGES=	singleuser
CHERI_DE4_2THREAD_MDROOT_IMAGES=	singleuser
CHERI_DE4_MDROOT_IMAGES=	net singleuser smoketest smoketest_bootonly
CHERI_SIM_MDROOT_IMAGES=	net singleuser smoketest smoketest_bootonly
CHERI_SIM_2CORE_MDROOT_IMAGES=	singleuser
CHERI_SIM_2THREAD_MDROOT_IMAGES=	singleuser
CHERI_SOCKIT_MDROOT_IMAGES=	singleuser
CHERI128_SIM_MDROOT_IMAGES=	net singleuser smoketest smoketest_bootonly
CHERI128_DE4_MDROOT_IMAGES=	net singleuser smoketest smoketest_bootonly

QEMU_DISKIMAGE?=	${PRODUCT}-smoketest_bootonly.img
.if defined(CHERI) && ${CHERI} == 256
QEMU_KERNEL?=		${PRODUCT}-cheri-malta64-kernel
QEMU_CMD?=		qemu-system-cheri
.elif defined(CHERI) && ${CHERI} == 128
QEMU_KERNEL?=		${PRODUCT}-cheri128-malta64-kernel
QEMU_CMD?=		qemu-system-cheri128
.elif defined(BERI)
QEMU_KERNEL?=		${PRODUCT}-malta64-kernel
QEMU_CMD?=		qemu-system-cheri
.endif
.if !defined(QEMU_SSH_PORT)
QEMU_SSH_PORT!=		id -u
.endif

all:
	${MAKE} world
	${MAKE} images
	${MAKE} kernels
.if ${BASE_ABI} != "cheriabi_static"
	${MAKE} sdcard
.endif
	${MAKE} full

.if !defined(ROOTDIR)
.error You must set ROOTDIR
.endif

MAKEVARS=	TARGET=mips TARGET_ARCH=mips64 \
		DEBUG_FLAGS=-g \
		-DDB_FROM_SRC -DNO_ROOT

.if defined(CHERI)
.if ${CHERI} != "128" && ${CHERI} != "256"
.error CHERI must be set to either 128 or 256
.endif
.if !defined(CHERI_CC)
.error You must set CHERI_CC when building for CHERI
.endif
.if ${CHERI} == "256"
PRODUCT=	cheribsd
.else
PRODUCT=	cheribsd${CHERI}
.endif
KERNELS?=	${CHERI${CHERI}_KERNELS}
MAKEVARS+=	-DWITH_CHERI${CHERI}
WORLDVARS+=	CHERI_CC=${CHERI_CC}
WORLDVARS+=	-DWITH_CHERI_USE_LLD
.if ${KERNELS:MCHERI_DE4_MDROOT}
FLASH_BASE=	CHERI_DE4_MDROOT
.endif
.if ${KERNELS:MCHERI_DE4_SDROOT}
SDKERNEL=	CHERI_DE4_SDROOT
.elif ${KERNELS:MCHERI128_DE4_SDROOT}
SDKERNEL=	CHERI128_DE4_SDROOT
.endif
.elif defined(BERI)
PRODUCT=	freebsd
KERNELS?=	${BERI_KERNELS}
FLASH_BASE=	BERI_DE4_MDROOT
SDKERNEL=	BERI_DE4_SDROOT
.else
.error Either BERI or CHERI must be defined
.endif
.ifndef OLD_FDT_KERNELS
KERNELS:=	${KERNELS:N*2CORE*:N*2THREAD*}
.endif

.ifdef NO_CLEAN
WORLDVARS+=	-DNO_CLEAN
.endif

.if ${BASE_ABI:Mcheriabi*}
WORLDVARS+=	-DWITH_CHERI_PURE
.if !${BASE_ABI:M*static}
WORLDVARS+=	-DWITH_CHERI_SHARED_PROG
.endif
.endif

PRODUCT_ROOTDIR= ${ROOTDIR}/${PRODUCT}

.SUFFIXES: .bz2 .bz2.md5 .dump .dump.bz2 .img .img.xz .debug .debug.bz2 \
    .tar .tar.xz -boot2 -boot2.bz2 -kernel -kernel.bz2
.bz2.bz2.md5:
	md5 ${.IMPSRC} > ${.TARGET}
.dump.dump.bz2:
	bzip2 -c ${.IMPSRC} > ${.TARGET}
.debug.debug.bz2:
	bzip2 -c ${.IMPSRC} > ${.TARGET}
.img.img.xz:
	pxz -k ${.IMPSRC}
.tar.tar.xz:
	pxz -k ${.IMPSRC}
-boot2-boot2.bz2:
	bzip2 -c ${.IMPSRC} > ${.TARGET}
-kernel-kernel.bz2:
	bzip2 -c ${.IMPSRC} > ${.TARGET}


.PHONY: images
.PHONY: full
.PHONY:	image-full
full:	image-full
.PHONY: sdcard
.PHONY: image-sdcard
sdcard: image-sdcard
.PHONY: isca
.PHONY: image-isca
isca:	image-isca

.for IMAGE in ${IMAGES}
_INAME_${IMAGE}=	${PRODUCT}-${IMAGE}.img
.if ${IMAGE} == "full"
FULL_FILES+=	${_INAME_${IMAGE}} ${_INAME_${IMAGE}}.xz
.elif ${IMAGE} == "sdcard"
SDCARD_FILES+=	${_INAME_${IMAGE}} ${_INAME_${IMAGE}}.xz
.elif ${IMAGE} != "isca"
IMAGE_FILES+=   ${_INAME_${IMAGE}} ${_INAME_${IMAGE}}.xz
images: image-${IMAGE}
.endif
.if ${IMAGE} != "isca"
DATED_FILES+=	${DATESTAMP}-${_INAME_${IMAGE}}.xz
.endif
image-${IMAGE}: ${_INAME_${IMAGE}}.xz
${_INAME_${IMAGE}}: ${PRODUCT_ROOTDIR}/METALOG ${EXTRAS_${IMAGE}} \
    ${FILES_${IMAGE}} ${EXTRAS_DIR}/etc/master.passwd \
    ${EXTRAS_DIR}/etc/group ${EXTRAS_DIR}/ctsrd.mtree
	${MAKEROOT} -k ${KEY_DIR} -K ctsrd \
	    -p ${EXTRAS_DIR}/etc/master.passwd -g ${EXTRAS_DIR}/etc/group \
	    ${EXTRAS_${IMAGE}:C/(..*)/-e \1/} \
	    -e ${EXTRAS_DIR}/ctsrd.mtree \
	    ${SIZE_${IMAGE}:C/(..*)/-s \1/} \
	    ${INODES_${IMAGE}:C/(..*)/-F \1/} \
	    ${FILES_${IMAGE}:C/(..*)/-f \1/}$ \
	    ${EXCLUDE_${IMAGE}:Q:C/(..*)/-X \1/} \
	    ${.TARGET} ${PRODUCT_ROOTDIR}
.if ${IMAGE} == "full" && defined(BOOTSTRAP_KYUA) && ${BOOTSTRAP_KYUA} != "no"
	env QEMU_CMD=${QEMU_CMD} QEMU_KERNEL=${QEMU_KERNEL} \
	    QEMU_DISKIMAGE=${.TARGET} python bootstrap-kyua.py || \
	    rm -f ${.TARGET}
.endif

${DATESTAMP}-${_INAME_${IMAGE}}.xz: ${_INAME_${IMAGE}}.xz
	cp ${_INAME_${IMAGE}}.xz ${.TARGET}
.endfor

IMAGE_FILES+=	${PRODUCT}-world.tar ${PRODUCT}-world.tar.xz
DATED_FILES+=	${DATESTAMP}-${PRODUCT}-world.tar.xz
images: ${PRODUCT}-world.tar.xz
${PRODUCT}-world.tar: ${PRODUCT_ROOTDIR}/METALOG
	cd ${PRODUCT_ROOTDIR}; \
	    grep -B 99999 "# pre-distribution" METALOG | \
	    tar -cf ${.OBJDIR}/${.TARGET} @-

${DATESTAMP}-${PRODUCT}-world.tar.xz: ${PRODUCT}-world.tar.xz
	cp ${PRODUCT}-world.tar.xz ${.TARGET}

IMAGE_FILES+=	${PRODUCT}-distribution.tar ${PRODUCT}-distribution.tar.xz
DATED_FILES+=	${DATESTAMP}-${PRODUCT}-distribution.tar.xz
images: ${PRODUCT}-distribution.tar.xz
${PRODUCT}-distribution.tar: ${PRODUCT_ROOTDIR}/METALOG
	cd ${PRODUCT_ROOTDIR}; \
	    grep -A 99999 "# pre-distribution" METALOG | \
	    grep -B 99999 "# post-distribution" | \
	    tar -cf ${.OBJDIR}/${.TARGET} @-

${DATESTAMP}-${PRODUCT}-distribution.tar.xz: ${PRODUCT}-distribution.tar.xz
	cp ${PRODUCT}-distribution.tar.xz ${.TARGET}

REPODIR?=	${.CURDIR}/pkg-repo
PKG_DB_DIR=	${.CURDIR}/pkg-db
PKG_REPOS_DIR=	${.CURDIR}/pkg-repos

pkg-repo: ${PRODUCT}-pkg-repo.mtree

REPO_FILES+=	pkg.conf
pkg.conf:
	echo "ABI: freebsd:12:mips:64:eb:n64" > ${.TARGET}
	echo "PKG_DBDIR: ${PKG_DB_DIR}" >> ${.TARGET}
	echo "REPOS_DIR: [${PKG_REPOS_DIR}]" >> ${.TARGET}

${REPODIR}/meta.txz: pkg.conf
	rm -rf ${REPODIR}
	INSTALL_AS_USER=yes pkg --config=pkg.conf update
	INSTALL_AS_USER=yes pkg --config=pkg.conf fetch -o ${REPODIR} -Udy kyua pkg
	cd ${REPODIR}; rm -f kyua*; fetch https://people.freebsd.org/~sson/mips/packages/kyua-0.13_1,3.txz
	INSTALL_AS_USER=yes pkg --config=pkg.conf repo ${REPODIR}
	mkdir ${REPODIR}/Latest
	cd ${REPODIR}/Latest && ln ../All/pkg-1* pkg.txz

REPO_FILES+=	${PRODUCT}-pkg-repo.mtree
${PRODUCT}-pkg-repo.mtree: ${REPODIR}/meta.txz
	rm -f ${.TARGET}
	echo "./var/db/pkg-cache type=dir uname=root gname=wheel mode=755" >> ${.TARGET}
	echo "./var/db/pkg-cache/All type=dir uname=root gname=wheel mode=755" >> ${.TARGET}
	echo "./var/db/pkg-cache/Latest type=dir uname=root gname=wheel mode=755" >> ${.TARGET}
	(cd ${REPODIR}; find . -type f) | awk \
	    '{print "./var/db/pkg-cache/" $$1 \
	    " type=file uname=root gname=wheel mode=644 contents=${REPODIR}/" \
	    $$1}' >> ${.TARGET}

.if make(world) || make(kernels)
.if !defined(SRCDIR)
.error You must set at least one of SRCDIR for the world target
.endif
.if defined(SRCDIR) && !defined(PRODUCT_ROOTDIR)
.error You must set both SRCDIR and PRODUCT_ROOTDIR
.endif
.endif

KERNVARS=	${MAKEVARS}
WORLDVARS+=	${MAKEVARS} \
		-DMALLOC_PRODUCTION \
		-DWITH_DEBUG_FILES

.ifdef CHERI
WORLDVARS+=	LOCAL_DIRS="ctsrd tools/tools/atsectl" \
		LOCAL_LIB_DIRS=ctsrd/lib \
		LOCAL_MTREE=ctsrd/ctsrd.mtree
.endif

.PHONY: flash
flash:

kernels:
.for KERN in ${KERNELS}
	make ${KERN}.kernel
.endfor

.PHONY: world
world:

.if defined(SRCDIR)
OBJDIR!=	printf "${MAKEOBJDIRPREFIX}/mips.mips64%s" `realpath ${SRCDIR}`
.endif

.if defined(FLASH_BASE)
_KNAME_FLASH_BASE=${PRODUCT}-${FLASH_BASE:S/_/-/g:tl}-kernel
.endif

.for KERN in ${KERNELS}
_KNAME_${KERN}=	${PRODUCT}-${KERN:S/_/-/g:tl}-kernel
KERNEL_FILES+=	${_KNAME_${KERN}} ${_KNAME_${KERN}}.bz2 \
		${_KNAME_${KERN}}.dump ${_KNAME_${KERN}}.dump.bz2 \
		${_KNAME_${KERN}}.debug ${_KNAME_${KERN}}.debug.bz2
KERN_OBJDIRS+=	${OBJDIR}/sys/${KERN}
.if "${${KERN}_IMAGES}" == ""
DATED_FILES+=	${DATESTAMP}-${_KNAME_${KERN}}.bz2
.endif
DATED_FILES+=	${DATESTAMP}-${_KNAME_${KERN}}.dump.bz2 \
		${DATESTAMP}-${_KNAME_${KERN}}.debug.bz2

.PHONY: ${KERN}.kernel
${KERN}.kernel: ${_KNAME_${KERN}}.bz2 ${_KNAME_${KERN}}.dump.bz2 \
     ${_KNAME_${KERN}}.debug.bz2

${OBJDIR}/sys/${KERN}/kernel.full: ${SRCDIR}/sys/mips/conf/${KERN}
	cd ${SRCDIR}; MAKEOBJDIRPREFIX=${MAKEOBJDIRPREFIX} make ${KERNVARS} KERNCONF=${KERN} buildkernel
.if ${KERN} == ${SDKERNEL:Unonexistant}
	cd ${SRCDIR}; MAKEOBJDIRPREFIX=${MAKEOBJDIRPREFIX} make ${KERNVARS} KERNCONF=${KERN} \
	    DESTDIR=${PRODUCT_ROOTDIR} installkernel
.endif

${_KNAME_${KERN}}: ${OBJDIR}/sys/${KERN}/kernel.full
	cp ${OBJDIR}/sys/${KERN}/kernel ${.TARGET}

${_KNAME_${KERN}}.dump: ${OBJDIR}/sys/${KERN}/kernel.full
	${OBJDIR}/tmp/usr/bin/objdump -dS \
	    ${OBJDIR}/sys/${KERN}/kernel.full > \
	    ${.TARGET}

${_KNAME_${KERN}}.debug: ${OBJDIR}/sys/${KERN}/kernel.full
	cp ${OBJDIR}/sys/${KERN}/kernel.debug ${.TARGET}

${DATESTAMP}-${_KNAME_${KERN}}.bz2: ${_KNAME_${KERN}}.bz2
	cp ${_KNAME_${KERN}}.bz2 ${.TARGET}

${DATESTAMP}-${_KNAME_${KERN}}.dump.bz2: ${_KNAME_${KERN}}.dump.bz2
	cp ${_KNAME_${KERN}}.dump.bz2 ${.TARGET}

${DATESTAMP}-${_KNAME_${KERN}}.debug.bz2: ${_KNAME_${KERN}}.debug.bz2
	cp ${_KNAME_${KERN}}.debug.bz2 ${.TARGET}

.for IMAGE in ${${KERN}_IMAGES}
_KNAME_${KERN}${IMAGE}=	${_KNAME_${KERN}:S/-kernel/-${IMAGE}-kernel/}
KERNEL_FILES+=   ${_KNAME_${KERN}${IMAGE}} ${_KNAME_${KERN}${IMAGE}}.bz2
DATED_FILES+=   ${DATESTAMP}-${_KNAME_${KERN}${IMAGE}}.bz2

kernels: ${_KNAME_${KERN}${IMAGE}}.bz2

${_KNAME_${KERN}${IMAGE}}: ${_KNAME_${KERN}} ${PRODUCT}-${IMAGE}.img
	cp ${_KNAME_${KERN}} ${_KNAME_${KERN}${IMAGE}}
	sh ${SRCDIR}/sys/tools/embed_mfs.sh ${_KNAME_${KERN}${IMAGE}} \
	    ${PRODUCT}-${IMAGE}.img

${DATESTAMP}-${_KNAME_${KERN}${IMAGE}}.bz2: ${_KNAME_${KERN}${IMAGE}}.bz2
	cp ${_KNAME_${KERN}${IMAGE}}.bz2 ${.TARGET}

.if defined(FLASH_BASE) && ${KERN:M*_DE4_*}
### FLASH
# There are three almost identical copies of this code.  The one delimited
# by /^### FLASH$/ marks is the primary.  The second copy directly below
# and outside the IMAGE loop is delimited by /^### FLASH2$/ is a copy of
# it with all expansions of the IMAGE variable removed.  The third
# hardcodes jtagboot in the "kernel" postion creating a boot2 writing
# image and is delimated by /^### FLASH3$/.  Edit the first copy and then
# update the other when making changes.
FLASH_FILES+=	${_KNAME_${KERN}${IMAGE}}.bz2.md5 \
		flash-${_KNAME_${KERN}${IMAGE}} \
		flash-${_KNAME_${KERN}${IMAGE}}.bz2 \
		flash-${_KNAME_${KERN}${IMAGE}}.conf \
		flash-${_KNAME_${KERN}${IMAGE}}.img \
		flash-${_KNAME_${KERN}${IMAGE}}.mtree
DATED_FILES+=	${DATESTAMP}-flash-${_KNAME_${KERN}${IMAGE}}.bz2

flash: flash-${_KNAME_${KERN}${IMAGE}}.bz2

flash-${_KNAME_${KERN}${IMAGE}}: ${_KNAME_FLASH_BASE} \
    flash-${_KNAME_${KERN}${IMAGE}}.img
	cp ${_KNAME_FLASH_BASE} ${.TARGET}
	sh ${SRCDIR}/sys/tools/embed_mfs.sh ${.TARGET} \
	    flash-${_KNAME_${KERN}${IMAGE}}.img

flash-${_KNAME_${KERN}${IMAGE}}.img: \
    ${EXTRAS_DIR}/flashprep.tree prep-de4-flash.files \
    ${_KNAME_${KERN}${IMAGE}}.bz2 ${_KNAME_${KERN}${IMAGE}}.bz2.md5 \
    flash-${_KNAME_${KERN}${IMAGE}}.conf \
    flash-${_KNAME_${KERN}${IMAGE}}.mtree
	${MAKEROOT} -f prep-de4-flash.files \
	    -e ${EXTRAS_DIR}/flashprep.tree \
	    -e flash-${_KNAME_${KERN}${IMAGE}}.mtree \
	    ${.TARGET} ${PRODUCT_ROOTDIR}

flash-${_KNAME_${KERN}${IMAGE}}.conf:
	rm -f ${.TARGET}
	echo "kernel:${_KNAME_${KERN}${IMAGE}}.bz2" >> ${.TARGET}
	echo "fpga:${BITFILE:T}" >> ${.TARGET}

FILE_MTREE=type=file uname=root gname=wheel mode=644
flash-${_KNAME_${KERN}${IMAGE}}.mtree:
	rm -f ${.TARGET}
	echo "./upgrades/upgrade.conf ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/flash-${_KNAME_${KERN}${IMAGE}}.conf" >> \
	    ${.TARGET}
	echo "./upgrades/${_KNAME_${KERN}${IMAGE}}.bz2 ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/${_KNAME_${KERN}${IMAGE}}.bz2" >> ${.TARGET}
	echo "./upgrades/${_KNAME_${KERN}${IMAGE}}.bz2.md5 ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/${_KNAME_${KERN}${IMAGE}}.bz2.md5" >> \
	    ${.TARGET}
	echo "./upgrades/${BITFILE:T} ${FILE_MTREE} contents=${BITFILE}" >> \
	    ${.TARGET}
	echo "./upgrades/${BITFILE:T}.md5 ${FILE_MTREE}" \
	    "contents=${BITFILE}.md5" >> ${.TARGET}

${DATESTAMP}-flash-${_KNAME_${KERN}${IMAGE}}.bz2: \
    flash-${_KNAME_${KERN}${IMAGE}}.bz2
	cp flash-${_KNAME_${KERN}${IMAGE}}.bz2 ${.TARGET}
### FLASH
.endif
.endfor
.if defined(FLASH_BASE) && !defined(${KERN}_IMAGES) && ${KERN:M*_DE4_*}
### FLASH2
# There are three almost identical copies of this code.  The one delimited
# by /^### FLASH$/ marks is the primary.  The second copy directly below
# and outside the IMAGE loop is delimited by /^### FLASH2$/ is a copy of
# it with all expansions of the IMAGE variable removed.  The third
# hardcodes jtagboot in the "kernel" postion creating a boot2 writing
# image and is delimated by /^### FLASH3$/.  Edit the first copy and then
# update the other when making changes.
FLASH_FILES+=	${_KNAME_${KERN}}.bz2.md5 \
		flash-${_KNAME_${KERN}} \
		flash-${_KNAME_${KERN}}.bz2 \
		flash-${_KNAME_${KERN}}.conf \
		flash-${_KNAME_${KERN}}.img \
		flash-${_KNAME_${KERN}}.mtree
DATED_FILES+=	${DATESTAMP}-flash-${_KNAME_${KERN}}.bz2

flash: flash-${_KNAME_${KERN}}.bz2

flash-${_KNAME_${KERN}}: ${_KNAME_FLASH_BASE} \
    flash-${_KNAME_${KERN}}.img
	cp ${_KNAME_FLASH_BASE} ${.TARGET}
	sh ${SRCDIR}/sys/tools/embed_mfs.sh ${.TARGET} \
	    flash-${_KNAME_${KERN}}.img

flash-${_KNAME_${KERN}}.img: \
    ${EXTRAS_DIR}/flashprep.tree prep-de4-flash.files \
    ${_KNAME_${KERN}}.bz2 ${_KNAME_${KERN}}.bz2.md5 \
    flash-${_KNAME_${KERN}}.conf \
    flash-${_KNAME_${KERN}}.mtree
	${MAKEROOT} -f prep-de4-flash.files \
	    -e ${EXTRAS_DIR}/flashprep.tree \
	    -e flash-${_KNAME_${KERN}}.mtree \
	    ${.TARGET} ${PRODUCT_ROOTDIR}

flash-${_KNAME_${KERN}}.conf:
	rm -f ${.TARGET}
	echo "kernel:${_KNAME_${KERN}}.bz2" >> ${.TARGET}
	echo "fpga:${BITFILE:T}" >> ${.TARGET}

FILE_MTREE=type=file uname=root gname=wheel mode=644
flash-${_KNAME_${KERN}}.mtree:
	rm -f ${.TARGET}
	echo "./upgrades/upgrade.conf ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/flash-${_KNAME_${KERN}}.conf" >> \
	    ${.TARGET}
	echo "./upgrades/${_KNAME_${KERN}}.bz2 ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/${_KNAME_${KERN}}.bz2" >> ${.TARGET}
	echo "./upgrades/${_KNAME_${KERN}}.bz2.md5 ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/${_KNAME_${KERN}}.bz2.md5" >> \
	    ${.TARGET}
	echo "./upgrades/${BITFILE:T} ${FILE_MTREE} contents=${BITFILE}" >> \
	    ${.TARGET}
	echo "./upgrades/${BITFILE:T}.md5 ${FILE_MTREE}" \
	    "contents=${BITFILE}.md5" >> ${.TARGET}

${DATESTAMP}-flash-${_KNAME_${KERN}}.bz2: \
    flash-${_KNAME_${KERN}}.bz2
	cp flash-${_KNAME_${KERN}}.bz2 ${.TARGET}
.undef IMAGE
### FLASH2
.endif
.endfor

.if defined(FLASH_BASE)
### FLASH3
# There are three almost identical copies of this code.  The one delimited
# by /^### FLASH$/ marks is the primary.  The second copy directly below
# and outside the IMAGE loop is delimited by /^### FLASH2$/ is a copy of
# it with all expansions of the IMAGE variable removed.  The third
# hardcodes jtagboot in the "kernel" postion creating a boot2 writing
# image and is delimated by /^### FLASH3$/.  Edit the first copy and then
# update the other when making changes.
FLASH_FILES+=	\
		flash-${PRODUCT}-boot2 \
		flash-${PRODUCT}-boot2.bz2 \
		flash-${PRODUCT}-boot2.conf \
		flash-${PRODUCT}-boot2.img \
		flash-${PRODUCT}-boot2.mtree
DATED_FILES+=	${DATESTAMP}-flash-${PRODUCT}-boot2.bz2

flash: flash-${PRODUCT}-boot2.bz2

flash-${PRODUCT}-boot2: ${_KNAME_FLASH_BASE} \
    flash-${PRODUCT}-boot2.img
	cp ${_KNAME_FLASH_BASE} ${.TARGET}
	sh ${SRCDIR}/sys/tools/embed_mfs.sh ${.TARGET} \
	    flash-${PRODUCT}-boot2.img

flash-${PRODUCT}-boot2.img: \
    ${EXTRAS_DIR}/flashprep.tree prep-de4-flash.files \
    ${PRODUCT}-jtagboot ${PRODUCT}-jtagboot.md5 \
    flash-${PRODUCT}-boot2.conf \
    flash-${PRODUCT}-boot2.mtree
	${MAKEROOT} -f prep-de4-flash.files \
	    -e ${EXTRAS_DIR}/flashprep.tree \
	    -e flash-${PRODUCT}-boot2.mtree \
	    ${.TARGET} ${PRODUCT_ROOTDIR}

flash-${PRODUCT}-boot2.conf:
	rm -f ${.TARGET}
	echo "kernel:${PRODUCT}-jtagboot" >> ${.TARGET}
	echo "fpga:${BITFILE:T}" >> ${.TARGET}

FILE_MTREE=type=file uname=root gname=wheel mode=644
flash-${PRODUCT}-boot2.mtree:
	rm -f ${.TARGET}
	echo "./upgrades/upgrade.conf ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/flash-${PRODUCT}-boot2.conf" >> \
	    ${.TARGET}
	echo "./upgrades/${PRODUCT}-jtagboot ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/${PRODUCT}-jtagboot" >> ${.TARGET}
	echo "./upgrades/${PRODUCT}-jtagboot.md5 ${FILE_MTREE}" \
	    "contents=${.OBJDIR}/${PRODUCT}-jtagboot.md5" >> \
	    ${.TARGET}
	echo "./upgrades/${BITFILE:T} ${FILE_MTREE} contents=${BITFILE}" >> \
	    ${.TARGET}
	echo "./upgrades/${BITFILE:T}.md5 ${FILE_MTREE}" \
	    "contents=${BITFILE}.md5" >> ${.TARGET}

${DATESTAMP}-flash-${PRODUCT}-boot2.bz2: \
    flash-${PRODUCT}-boot2.bz2
	cp flash-${PRODUCT}-boot2.bz2 ${.TARGET}
.undef IMAGE
### FLASH3
.endif

WORLD_FILES+=	${PRODUCT}-flashboot ${PRODUCT}-flashboot.md5 \
		${PRODUCT}-jtagboot ${PRODUCT}-jtagboot.md5
WORLD_DIRS+=	${PRODUCT_ROOTDIR}
world:
.if !defined(NO_CLEAN)
	rm -rf ${PRODUCT_ROOTDIR}
.endif
	cd ${SRCDIR}; make ${WORLDVARS} buildworld
	mkdir -p ${PRODUCT_ROOTDIR}
	cd ${SRCDIR}; \
	    make ${WORLDVARS} DESTDIR=${PRODUCT_ROOTDIR} \
	     installworld && \
	    echo "# pre-distribution" >> ${PRODUCT_ROOTDIR}/METALOG && \
	    make ${WORLDVARS} DESTDIR=${PRODUCT_ROOTDIR} \
		distribution && \
	    echo "# post-distribution" >> ${PRODUCT_ROOTDIR}/METALOG
	install -m 644 ${PRODUCT_ROOTDIR}/boot/flashboot \
	    ${.OBJDIR}/${PRODUCT}-flashboot
	install -m 644 ${PRODUCT_ROOTDIR}/boot/flashboot.md5 \
	    ${.OBJDIR}/${PRODUCT}-flashboot.md5
	install -m 644 ${PRODUCT_ROOTDIR}/boot/jtagboot \
	    ${.OBJDIR}/${PRODUCT}-jtagboot
	install -m 644 ${PRODUCT_ROOTDIR}/boot/jtagboot.md5 \
	    ${.OBJDIR}/${PRODUCT}-jtagboot.md5

DATED_FILES+=	${DATESTAMP}-${PRODUCT}-flashboot
DATED_FILES+=	${DATESTAMP}-${PRODUCT}-flashboot.md5
DATED_FILES+=	${DATESTAMP}-${PRODUCT}-jtagboot
DATED_FILES+=	${DATESTAMP}-${PRODUCT}-jtagboot.md5
${DATESTAMP}-${PRODUCT}-flashboot: ${PRODUCT}-flashboot
	cp ${PRODUCT}-flashboot ${.TARGET}

${DATESTAMP}-${PRODUCT}-flashboot.md5: ${PRODUCT}-flashboot.md5
	cp ${PRODUCT}-flashboot.md5 ${.TARGET}

${DATESTAMP}-${PRODUCT}-jtagboot: ${PRODUCT}-jtagboot
	cp ${PRODUCT}-jtagboot ${.TARGET}

${DATESTAMP}-${PRODUCT}-jtagboot.md5: ${PRODUCT}-jtagboot.md5
	cp ${PRODUCT}-jtagboot.md5 ${.TARGET}

.PHONY: dated
dated: ${DATED_FILES}

DATED_FILES+=	${DATESTAMP}-${PRODUCT}-cheritest_list.xml
${DATESTAMP}-${PRODUCT}-cheritest_list.xml: ${PRODUCT}-cheritest_list.xml
	cp ${PRODUCT}-cheritest_list.xml ${.TARGET}
DATED_FILES+=	${DATESTAMP}-${PRODUCT}-cheriabitest_list.xml
${DATESTAMP}-${PRODUCT}-cheriabitest_list.xml: ${PRODUCT}-cheriabitest_list.xml
	cp ${PRODUCT}-cheriabitest_list.xml ${.TARGET}

TEST_FILES+=	${PRODUCT}-cheritest_list.xml
${PRODUCT}-cheritest_list.xml: ${OBJDIR}/tmp/bin/cheritest
	${OBJDIR}/tmp/bin/cheritest --libxo=xml,pretty -l > ${.TARGET}
TEST_FILES+=	${PRODUCT}-cheriabitest_list.xml
${PRODUCT}-cheriabitest_list.xml: ${OBJDIR}/tmp/bin/cheriabitest
	${OBJDIR}/tmp/bin/cheriabitest --libxo=xml,pretty -l > ${.TARGET}

TEST_FILES+=	${PRODUCT}-boot-test.xml
.PHONY: ${PRODUCT}-boot-test.xml
${PRODUCT}-boot-test.xml: ${PRODUCT}-cheritest_list.xml ${PRODUCT}-cheriabitest_list.xml test_qemu_boot.py ${QEMU_KERNEL} ${QEMU_DISKIMAGE}
	QEMU_KERNEL=${QEMU_KERNEL} \
	QEMU_DISKIMAGE=${QEMU_DISKIMAGE} \
	QEMU_CMD=${QEMU_CMD} \
	CHERITEST_LIST_XML=${PRODUCT}-cheritest_list.xml \
	    CHERIABITEST_LIST_XML=${PRODUCT}-cheriabitest_list.xml nosetests -s \
	    --with-xunit --xunit-file=${.TARGET} test_qemu_boot.py \
	    || true
	@test -e ${.TARGET}

test-depends:	${PRODUCT}-cheritest_list.xml ${PRODUCT}-cheriabitest_list.xml

test:	${PRODUCT}-boot-test.xml

QEMU_DISKIMAGE_BOOT?=qemu-boot.img
${QEMU_DISKIMAGE_BOOT}: ${PRODUCT}-full.img
	cp ${PRODUCT}-full.img ${.TARGET}

qemu-boot: ${QEMU_KERNEL} ${QEMU_DISKIMAGE_BOOT}
	${QEMU_CMD} -M malta -kernel ${QEMU_KERNEL} \
	    -hda ${QEMU_DISKIMAGE_BOOT} \
	    -m 2048 -nographic -net nic -net user \
	    -redir tcp:${QEMU_SSH_PORT}::22

.PHONY: clean-test
clean-test:
	rm -f ${TEST_FILES}

.PHONY: clean-dated
clean-dated:
	rm -f ${DATED_FILES}

.PHONY: clean-flash
clean-flash:
	rm -f ${FLASH_FILES}

.PHONY: clean-images
clean-images:
	rm -f ${IMAGE_FILES}

.PHONY: clean-repos
clean-repos:
	rm -rf ${REPODIR} ${PKG_DB_DIR} ${REPO_FILES}

.PHONY: clean-kernels
clean-kernels:
	rm -rf ${KERN_OBJDIRS} ${KERNEL_FILES}

.PHONY: clean-full
clean-full:
	rm -f ${FULL_FILES}

.PHONY: clean-sdcard
clean-sdcard:
	rm -f ${SDCARD_FILES}

.PHONY: clean-isca
clean-isca:
	rm -f ${SDCARD_FILES}

.PHONY: clean-world
clean-world:
	rm -rf ${WORLD_DIRS}
	rm -f ${WORLD_FILES}

.PHONY: clean
clean:
	rm -f ${IMAGE_FILES} ${KERNEL_FILES} ${FLASH_FILES} ${SDCARD_FILES} \
	    ${WORLD_FILES}

.PHONY: realclean
realclean: clean clean-dated clean-full clean-isca clean-kernels clean-repos clean-sdcard clean-test clean-world
	rm -rf ${ROOTDIR}
