#!/bin/bash
#-
# Copyright (c) 2012-2014, 2016 SRI International
# Copyright (c) 2012 Robert N. M. Watson
# Copyright (c) 2016 A. Theodore Markettos
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
# $FreeBSD$

usage()
{
	cat <<EOF 1>&2
usage: tars2root.sh [-d (ebug)] [-e <extras manifest>] [-E <extras directory>]
                   [-k <keys directory>]
		   [-S <staging directory> ] [-s <size>] 
		   <image> <tarball> [<tarball> ...]
EOF
	exit 1
}

warn()
{
	echo `basename $0` "$@" 1>&2
}

err()
{
	ret=$1
	shift
	warn "$@"
	exit $ret
}

atexit()
{
	if [ -z "${DEBUG}" ]; then
		rm -rf ${tmpdir}
	else
		warn "temp directory left at ${tmpdir}"
	fi
}

add_tar_xz () {
	local TARXZ=$1
	local MTREE=$2
	local STAGING=$3

	echo "Adding $TARXZ to $MTREE"
	mkdir -p $STAGING
	tar Jxf $TARXZ -C $STAGING
	xzcat $TARXZ | \
	/usr/local/bin/bsdtar -cf - --format mtree --options='!all,type,uname,gname,mode,link' -C $STAGING @- > $TARXZ.mtree.orig
	sed s/uname=jenkins/uname=root/g < $TARXZ.mtree.orig | sed s/gname=jenkins/gname=wheel/g > $TARXZ.mtree

	cat $TARXZ.mtree >> $MTREE
}

DEBUG=
EXTRAS_MTREE=
EXTRAS_DIR=
FILELIST=
TMPDIR=
SIZE=
IMGFILE=

#WORLD=freebsd-world.tar.xz
#DISTRIBUTION=freebsd-distribution.tar.xz
#EXTRAS_DIR=bsdtools/extras
#EXTRAS_MTREE=bsdtools/extras/sdroot.mtree
#KEYS_DIR=bsdtools/keys
#STAGING=staging
#SIZE=4g
#IMGFILE=tree.img


while getopts "de:E:S:s:k:" opt; do
	case "$opt" in
	d)	DEBUG=1 ;;
	e)	EXTRAS_MTREE="${OPTARG}" ;;
	E)	EXTRAS_DIR="${OPTARG}";;
	S)	TMPDIR="${OPTARG}" ;;
	s)	SIZE="${OPTARG}" ;;
	k)	KEYS_DIR="${OPTARG}" ;;
	*)	echo "$opt" ; usage ;;
	esac
done
shift $(($OPTIND - 1))

if [ $# -lt 2 ]; then
	usage;
fi

IMGFILE=$(realpath $(dirname $1))/$(basename $1)

DBDIR=${BSDROOT}/etc

if [ "x$TMPDIR" = "x" ] ; then
#	tmpdir=`mktemp -d /tmp/trees2img.XXXXX`
	tmpdir=staging
fi
mkdir -p $TMPDIR
if [ -z "$TMPDIR" -o ! -d "$TMPDIR" ]; then
	err 1 "failed to create tmpdir"
fi
trap atexit EXIT

shift
rm -f $IMGFILE.mtree

for TARBALL in $@ ; do
	add_tar_xz $TARBALL $IMGFILE.mtree $TMPDIR
done

#tar Jxf $WORLD -C $STAGING
#xzcat $WORLD | tar -cf - --format mtree --options='!all,type,uname,gname,mode,link' -C $STAGING @- > $WORLD.mtree

#tar Jxf $DISTRIBUTION -C $STAGING
#mtree -c -i -p / -K type,sha1digest > ../world.mtree
#xzcat $DISTRIBUTION | tar -cf - --format mtree --options='!all,type,uname,gname,mode,link' -C $STAGING @- >> $WORLD.mtree

echo "#mtree 2.0" > $TMPDIR/METALOG
echo ". type=dir uname=root gname=wheel mode=0755" >> $TMPDIR/METALOG
tail -n +3 $IMGFILE.mtree >> $TMPDIR/METALOG

#cat ../$EXTRAS >> ../world.mtree
#tar -Jcvf ../tree.tar @../world.mtree

PARAMS="-B big"

if [ "x$SIZE" != "x" ] ; then
	PARAMS="$PARAMS -s $SIZE"
fi

if [ "x$EXTRAS_MTREE" != "x" ] ; then
	cp -a $EXTRAS_DIR/* $TMPDIR/
	PARAMS="$PARAMS -e $EXTRAS_MTREE -p $EXTRAS_DIR/etc/master.passwd -g $EXTRAS_DIR/etc/group"
else
	echo "Not adding any extras"
fi

if [ "x$KEYS_DIR" != "x" ] ; then
	PARAMS="$PARAMS -k $KEYS_DIR"
fi

if [ "x$DEBUG" != "x" ] ; then
	PARAMS="$PARAMS -d"
	echo "makeroot.sh $PARAMS $IMGFILE $TMPDIR"
fi

makeroot.sh $PARAMS $IMGFILE $TMPDIR

echo "xz compressing $IMGFILE"
pxz $IMGFILE
