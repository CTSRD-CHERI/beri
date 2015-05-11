#-
# Copyright (c) 2013-2014 SRI International
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
#

MAKEROOT?=	${.CURDIR}/makeroot.sh -B big
DEMO_DIR?=	${.CURDIR}/demo
EXTRAS_DIR?=	${.CURDIR}/extras
KEY_DIR?=	${.CURDIR}/keys

.sinclude "Makefile.conf"

.if !defined(DATESTAMP)
DATESTAMP!=	date +%Y%m%d
.endif

PRODUCT=	cheribsd

EXTRAS_demo=	${EXTRAS_DIR}/autosd.mtree ${EXTRAS_DIR}/mdroot.mtree ${DEMO_DIR}/demo.mtree
FILES_demo=	${.CURDIR}/demo.files
SIZE_demo=	26112k

EXTRAS_net=	${EXTRAS_DIR}/sdroot.mtree
FILES_net=	${.CURDIR}/net.files
SIZE_net=	26112k

EXTRAS_sdcard=	${EXTRAS_DIR}/sdroot.mtree
SIZE_sdcard=	1800m

EXTRAS_smoketest=	${EXTRAS_DIR}/smoketest.mtree
FILES_smoketest=	${.CURDIR}/smoketest.files

EXTRAS_smoketest_bootonly=	${EXTRAS_DIR}/smoketest-bootonly.mtree
FILES_smoketest_bootonly=	${.CURDIR}/smoketest.files

EXTRAS_isca=	${EXTRAS_DIR}/isca.mtree ${DEMO_DIR}/demo.mtree
SIZE_isca=	1200m

SIZE_singleuser=	26112k
FILES_singleuser=	${.CURDIR}/singleuser.files

KERNELS=	BERI_DE4_2CORE_MDROOT BERI_DE4_2THREAD_MDROOT \
		BERI_DE4_MDROOT BERI_DE4_USBROOT BERI_SIM_MDROOT \
		BERI_DE4_SDROOT \
		BERI_SIM_2CORE_MDROOT BERI_SIM_2THREAD_MDROOT \
		BERI_SOCKIT_MDROOT \
		CHERI_DE4_2CORE_MDROOT CHERI_DE4_2THREAD_MDROOT \
		CHERI_DE4_SDROOT CHERI_DE4_NFSROOT CHERI_DE4_USBROOT \
		CHERI_SIM_MDROOT \
		CHERI_SIM_2CORE_MDROOT CHERI_SIM_2THREAD_MDROOT \
		CHERI_SOCKIT_MDROOT \
		${FLASH_BASE}
FLASH_BASE=	CHERI_DE4_MDROOT
SDKERNEL=	CHERI_DE4_SDROOT

IMAGES=	net sdcard singleuser smoketest smoketest_bootonly

BERI_DE4_2CORE_MDROOT_IMAGES=	singleuser
BERI_DE4_2THREAD_MDROOT_IMAGES=	singleuser
BERI_SIM_MDROOT_IMAGES=		singleuser smoketest smoketest_bootonly
BERI_SIM_2CORE_MDROOT_IMAGES=	singleuser
BERI_SIM_2THREAD_MDROOT_IMAGES=	singleuser
BERI_SOCKIT_MDROOT_IMAGES=	net singleuser
BERI_DE4_MDROOT_IMAGES=		singleuser smoketest_bootonly
CHERI_DE4_2CORE_MDROOT_IMAGES=	singleuser
CHERI_DE4_2THREAD_MDROOT_IMAGES=	singleuser
CHERI_DE4_MDROOT_IMAGES=	singleuser smoketest smoketest_bootonly
CHERI_SIM_MDROOT_IMAGES=	singleuser smoketest
CHERI_SIM_2CORE_MDROOT_IMAGES=	singleuser
CHERI_SIM_2THREAD_MDROOT_IMAGES=	singleuser
CHERI_SOCKIT_MDROOT_IMAGES=	singleuser

all:
	${MAKE} world
	${MAKE} images
	${MAKE} kernels
	${MAKE} sdcard
	${MAKE} flash

.if !defined(ROOTDIR)
.error You must set ROOTDIR
.endif

.SUFFIXES: .bz2 .bz2.md5 .dump .dump.bz2 .img .img.xz .symbols .symbols.bz2 \
    .tar .tar.xz -boot2 -boot2.bz2 -kernel -kernel.bz2
.bz2.bz2.md5:
	md5 ${.IMPSRC} > ${.TARGET}
.dump.dump.bz2:
	bzip2 -c ${.IMPSRC} > ${.TARGET}
.symbols.symbols.bz2:
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
.PHONY: sdcard
.PHONY: image-sdcard
sdcard: image-sdcard
.PHONY: isca
.PHONY: image-isca
isca:	image-isca

.for IMAGE in ${IMAGES}
_INAME_${IMAGE}=	${PRODUCT}-${IMAGE}.img
.if ${IMAGE} != "sdcard" && ${IMAGE} != "isca"
IMAGE_FILES+=	${_INAME_${IMAGE}} ${_INAME_${IMAGE}}.xz
images: image-${IMAGE}
.else
SDCARD_FILES+=	${_INAME_${IMAGE}} ${_INAME_${IMAGE}}.xz
.endif
.if ${IMAGE} != "isca"
DATED_FILES+=	${DATESTAMP}-${_INAME_${IMAGE}}.xz
.endif
image-${IMAGE}: ${_INAME_${IMAGE}}.xz
${_INAME_${IMAGE}}: ${ROOTDIR}/METALOG ${EXTRAS_${IMAGE}} \
    ${FILES_${IMAGE}} ${EXTRAS_DIR}/etc/master.passwd \
    ${EXTRAS_DIR}/etc/group ${EXTRAS_DIR}/ctsrd.mtree
	${MAKEROOT} -k ${KEY_DIR} -K ctsrd \
	    -p ${EXTRAS_DIR}/etc/master.passwd -g ${EXTRAS_DIR}/etc/group \
	    ${EXTRAS_${IMAGE}:C/(..*)/-e \1/} \
	    -e ${EXTRAS_DIR}/ctsrd.mtree \
	    ${SIZE_${IMAGE}:C/(..*)/-s \1/} \
	    ${FILES_${IMAGE}:C/(..*)/-f \1/}$ \
	    ${.TARGET} ${ROOTDIR}

${DATESTAMP}-${_INAME_${IMAGE}}.xz: ${_INAME_${IMAGE}}.xz
	cp ${_INAME_${IMAGE}}.xz ${.TARGET}
.endfor

IMAGE_FILES+=	${PRODUCT}-world.tar ${PRODUCT}-world.tar.xz
DATED_FILES+=	${DATESTAMP}-${PRODUCT}-world.tar.xz
images: ${PRODUCT}-world.tar.xz
${PRODUCT}-world.tar: ${ROOTDIR}/METALOG
	cd ${ROOTDIR}; \
	    grep -B 99999 "# pre-distribution" METALOG | \
	    tar -cf ${.OBJDIR}/${.TARGET} @-

${DATESTAMP}-${PRODUCT}-world.tar.xz: ${PRODUCT}-world.tar.xz
	cp ${PRODUCT}-world.tar.xz ${.TARGET}

.if make(world) || make(kernels)
.if !defined(SRCDIR)
.error You must set at least one of SRCDIR for the world target
.endif
.if defined(SRCDIR) && !defined(ROOTDIR)
.error You must set both SRCDIR and ROOTDIR
.endif
.endif

MAKEVARS=	TARGET=mips TARGET_ARCH=mips64 \
		DEBUG_FLAGS=-g -DDB_FROM_SRC -DNO_ROOT
KERNVARS=	${MAKEVARS}
WORLDVARS=	${MAKEVARS} \
		-DMALLOC_PRODUCTION \
		-DWITH_DEBUG_FILES \
		-DWITH_OPENSSH_NONE_CIPHER \
		-DWITHOUT_TESTS

.if defined(CHERI_CC)
WORLDVARS+=	CHERI_CC=${CHERI_CC} CHERI=256
.endif
WORLDVARS+=	LOCAL_DIRS="ctsrd tools/tools/atsectl" \
		LOCAL_LIB_DIRS=ctsrd/lib \
		LOCAL_MTREE=ctsrd/ctsrd.mtree

.PHONY: flash
flash:

.PHONY: kernels
kernels:

.PHONY: world
world:

.if defined(SRCDIR)
OBJDIR!=	printf "${MAKEOBJDIRPREFIX}/mips.mips64%s" `realpath ${SRCDIR}`
.endif

_KNAME_FLASH_BASE=${PRODUCT}-${FLASH_BASE:S/_/-/g:tl}-kernel

.for KERN in ${KERNELS}
_KNAME_${KERN}=	${PRODUCT}-${KERN:S/_/-/g:tl}-kernel
KERNEL_FILES+=	${_KNAME_${KERN}} ${_KNAME_${KERN}}.bz2 \
		${_KNAME_${KERN}}.dump ${_KNAME_${KERN}}.dump.bz2 \
		${_KNAME_${KERN}}.symbols ${_KNAME_${KERN}}.symbols.bz2
KERN_OBJDIRS+=	${OBJDIR}/sys/${KERN}
.if "${${KERN}_IMAGES}" == ""
DATED_FILES+=	${DATESTAMP}-${_KNAME_${KERN}}.bz2
.endif
DATED_FILES+=	${DATESTAMP}-${_KNAME_${KERN}}.dump.bz2 \
		${DATESTAMP}-${_KNAME_${KERN}}.symbols.bz2

kernels: ${_KNAME_${KERN}}.bz2 ${_KNAME_${KERN}}.dump.bz2 \
     ${_KNAME_${KERN}}.symbols.bz2

${OBJDIR}/sys/${KERN}/kernel.debug: ${SRCDIR}/sys/mips/conf/${KERN}
	cd ${SRCDIR}; make ${KERNVARS} KERNCONF=${KERN} buildkernel
.if ${KERN} == ${SDKERNEL}
	cd ${SRCDIR}; make ${KERNVARS} KERNCONF=${KERN} \
	    DESTDIR=${ROOTDIR} installkernel
.endif

${_KNAME_${KERN}}: ${OBJDIR}/sys/${KERN}/kernel.debug
	cp ${OBJDIR}/sys/${KERN}/kernel ${.TARGET}

${_KNAME_${KERN}}.dump: ${OBJDIR}/sys/${KERN}/kernel.debug
	${OBJDIR}/tmp/usr/bin/objdump -dS \
	    ${OBJDIR}/sys/${KERN}/kernel.debug > \
	    ${.TARGET}

${_KNAME_${KERN}}.symbols: ${OBJDIR}/sys/${KERN}/kernel.debug
	cp ${OBJDIR}/sys/${KERN}/kernel.symbols ${.TARGET}

${DATESTAMP}-${_KNAME_${KERN}}.bz2: ${_KNAME_${KERN}}.bz2
	cp ${_KNAME_${KERN}}.bz2 ${.TARGET}

${DATESTAMP}-${_KNAME_${KERN}}.dump.bz2: ${_KNAME_${KERN}}.dump.bz2
	cp ${_KNAME_${KERN}}.dump.bz2 ${.TARGET}

${DATESTAMP}-${_KNAME_${KERN}}.symbols.bz2: ${_KNAME_${KERN}}.symbols.bz2
	cp ${_KNAME_${KERN}}.symbols.bz2 ${.TARGET}

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

.if ${KERN:M*_DE4_*}
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
	    ${.TARGET} ${ROOTDIR}

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
.if !defined(${KERN}_IMAGES) && ${KERN:M*_DE4_*}
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
	    ${.TARGET} ${ROOTDIR}

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
	    ${.TARGET} ${ROOTDIR}

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

WORLD_FILES+=	${PRODUCT}-flashboot ${PRODUCT}-flashboot.md5 \
		${PRODUCT}-jtagboot ${PRODUCT}-jtagboot.md5
WORLD_DIRS+=	${ROOTDIR}
world:
.if !defined(NO_CLEAN)
	rm -rf ${ROOTDIR}
.endif
	cd ${SRCDIR}; make ${WORLDVARS} ${WORLDVARS} buildworld
	mkdir -p ${ROOTDIR}
	cd ${SRCDIR}; \
	    make ${WORLDVARS} ${WORLDVARS} DESTDIR=${ROOTDIR} \
	     installworld && \
	    echo "# pre-distribution" >> ${ROOTDIR}/METALOG && \
	    make ${WORLDVARS} DESTDIR=${ROOTDIR} \
		distribution
	install -m 644 ${ROOTDIR}/boot/flashboot \
	    ${.OBJDIR}/${PRODUCT}-flashboot
	install -m 644 ${ROOTDIR}/boot/flashboot.md5 \
	    ${.OBJDIR}/${PRODUCT}-flashboot.md5
	install -m 644 ${ROOTDIR}/boot/jtagboot \
	    ${.OBJDIR}/${PRODUCT}-jtagboot
	install -m 644 ${ROOTDIR}/boot/jtagboot.md5 \
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

.PHONY: clean-dated
clean-dated:
	rm -f ${DATED_FILES}

.PHONY: clean-flash
clean-flash:
	rm -f ${FLASH_FILES}

.PHONY: clean-images
clean-images:
	rm -f ${IMAGE_FILES}

.PHONY: clean-kernels
clean-kernels:
	rm -rf ${KERN_OBJDIRS} ${KERNEL_FILES}

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
realclean: clean clean-dated clean-isca clean-kernels clean-sdcard clean-world
	rm -rf ${ROOTDIR}
