#!/bin/sh
#-
# Copyright (c) 2012 SRI International
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

usage()
{
	echo "$0 <image>.sof"
	exit 1
}

if [ $# -ne 1 ]; then
	usage
fi

if [ ! -r "$1" ]; then
	echo "Can't open input file -- $1"
fi
sof_file=`readlink -f "$1"`
destdir=`dirname "${sof_file}"`

tmpdir=`mktemp -d`
echo $tmpdir
cd $tmpdir

# Put a copy or link of the file in $tmpdir so intermediate files end up there.
# This means cleanup easier and works around some tools not working on some
# nfs volumes (i.e. bigdisc at Cambridge).
case "${sof_file}" in
*.[Ss][Oo][Ff].bz2)
	base_file=`basename "${sof_file%.[Ss][Oo][Ff].bz2}"`
	bzcat "${sof_file}" > "${base_file}.sof"
	sof_file="${base_file}.sof"
	sof_file_is_tmp=true
	;;
*.[Ss][Oo][Ff])
	base_file=`basename "${sof_file%.[Ss][Oo][Ff]}"`
	ln -s "${sof_file}" "${base_file}.sof"
	sof_file="${base_file}.sof"
	;;
*)
	echo "Image must be a .sof(.bz2) file -- ${sof_file}"
	usage
	;;
esac

if ! sof2flash --input="${sof_file}" --output="${base_file}.flash" \
    --offset=0x00020000 --pfl --optionbit=0x18000 --programmingmode=FPP; then
    	echo "sof2flash failed."
	exit 1
fi
srec_cat "${base_file}.flash" -Output "${base_file}.bin" -binary
if [ $? -ne 0 ]; then
	echo "srec_cat failed."
	exit 1
fi
ls -l "${base_file}.bin"
size=`BLOCKSIZE=1m ls -s "${base_file}.bin"`
size=${size% *}
if [ $size -gt 24 ]; then
	echo "WARNING: File size exceeds 24MB!"
	ls -l "${base_file}.bin"
fi
bzip2 "${base_file}.bin"
cd `dirname "${sof_file}"`
openssl md5 `basename "${base_file}.bin.bz2"` > "${base_file}.bin.bz2.md5"

cp "${base_file}.bin.bz2" "${base_file}.bin.bz2.md5" "${destdir}/"

cd
echo "removing temp files"
rm -r "${tmpdir}"
