#!/bin/sh

#
# Copyright (c) 2012 Robert N. M. Watson
# Copyright (c) 2012 SRI International
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


#
# Script to produce a sample memory root file system for CHERI.  Populate with
# the minimal parts necessary to attempt (and demonstrate) entering single-user
# mode.
#
# XXXRW: Hard-coded path to mips64 world, not using mktemp.
#
# XXXRW: Doesn't require root per se, but doesn't ensure file owners/etc are
# correct in the image using mtree.
#
# $Id$
#

DIR0=$(dirname $(realpath "$0"))
BASEDIR=/home/brooks
BSDROOT=$BASEDIR/beribsd-root
IMGFILE=$BASEDIR/restore-flash.img
IMGDIR=$BASEDIR/restore-flash.dir
IMGMTREE=$BASEDIR/restore-flash.mtree

EXTRA_DIRS="dev tmp mnt etc upgrades"

FLASH_FILES="isf0:isf0-de4-terasic.bz2 isf1:isf1-de4-terasic.bz2"
FLASH_SRC="slogin-serv.cl.cam.ac.uk:/anfs/bigdisc/rnw24/cheri/"

FILELIST="${DIR0}/restore-flash.files"

if [ ! -r "${FILELIST}" ]; then
	err 1 "Expected to find filelist -- ${FILELIST}"
fi

#
# Scrub previous attempts
#
rm -Rf $IMGFILE $IMGDIR 2> /dev/null
chflags -Rf noschg $IMGFILE $IMGDIR 2>/dev/null
rm -Rf $IMGFILE $IMGDIR

#
# Size of the file system in K.  Must be <= the size declared in the BERI
# kernel configuration.
#
SIZE=8m

#
# Create the mdroot file system in $IMGDIR, then convert into a file system
# image named $IMG using makefs.
#
mkdir -p ${IMGDIR}
for dir in ${EXTRA_DIRS}; do
	mkdir -p "${IMGDIR}/${dir}"
done
(cd $BSDROOT ; tar -cf - --files-from ${FILELIST} ) | (cd $IMGDIR ; tar -xf -)
# Not yet.  Need new mtree.
#(cd $BSDROOT ; tar -cf ${IMGMTREE} --format mtree --options mtree:use-set --files-from ${FILELIST} )

cp ${DIR0}/../upgrade.sh ${IMGDIR}/upgrades/
while read line; do
	source="${line##*:}"
	if [ ! -r ${DIR0}/${source} ]; then
		scp ${FLASH_SRC}/${source} ${DIR0}
		scp ${FLASH_SRC}/${source}.md5 ${DIR0}
	fi
	cp ${DIR0}/${source} ${IMGDIR}/upgrades/
	cp ${DIR0}/${source}.md5 ${IMGDIR}/upgrades/
done < ${DIR0}/upgrade.conf
ln -s '/upgrades/upgrade.sh' ${IMGDIR}/etc/rc
cp ${DIR0}/upgrade.conf ${IMGDIR}/upgrades/
echo 

echo "md /tmp mfs rw,-s48m 2 0" >> $IMGDIR/etc/fstab
#makefs -B be -s $SIZE -F ${IMGMTREE} -t ffs -f 256 $IMGFILE $IMGDIR
makefs -B be -s $SIZE -t ffs -f 256 $IMGFILE $IMGDIR
