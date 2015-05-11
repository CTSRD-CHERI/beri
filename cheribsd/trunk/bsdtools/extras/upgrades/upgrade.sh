#!/bin/sh
#-
# Copyright (c) 2012-2013 SRI International
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
# This script is intended to be installed on SD Card upgrade file systems
# to run flashit to write updates to flash.  It is designed to be deployed
# without modification (other than feature additions) through out multiple
# update cycles.
#
# There must be an upgrade.conf file in the same directory as this
# script and it must contain lines of the form:
#
# <target>:<source>
#
# <target> is a target supported by the flashit script.  <source> is a
# file to be written to target.  The flashit script requires that
# <source>.md5 also exist and contain an MD5 checksum of the file.

err()
{
	ret=$1
	shift

	echo "${0##*/}:" "${@}" 1>&2
	exit $ret
}

echo "Beginning upgrade at `date`"

dir0=${0%/*}
if [ "${dir0}" = "${0}" ]; then
	if [ "${0}" -ef "./${0}" ]; then
		dir0=.
	else
		err 1 "$0 can not be run from \$PATH"
	fi
fi

runit()
{
	echo "${@}"
	"${@}"
}

# Allow the installer to provide it's own flashit program in case we're
# updating the flash layout.
flashit=/usr/sbin/flashit
if [ -x "${dir0}/flashit" ]; then
	flashit="${dir0}/flashit"
fi

if [ ! -r "$dir0/upgrade.conf" ]; then
	err 1 "missing or unreadable upgrade.conf"
fi

# Read the config file and make sure all the sources are readable to avoid
# a partial update.
# XXX: Should add a way to make sure the targets are valid.
while read line; do
	target="${line%%:*}"
	source="${line##*:}"

	if [ ! -r "${dir0}/${source}" ]; then
		err 1 "Can not read source '${source}' for target ${target}"
	fi
	
	targets="$targets $target"
	eval source_${target}="${dir0}/${source}"
done < "$dir0/upgrade.conf"

if [ -z "${targets}" ]; then
	err 1 "no targets found in $dir0/upgrade.conf"
fi

for target in $targets; do
	eval source=\$source_${target}
	if [ -z "$source" ]; then
		err 2 "INTERNAL ERROR: no source for target $target"
	fi

	if ! runit "${flashit}" "${target}" "${source}"; then
		err 1 "Upgrade failed in target $target"
	fi
done

echo "Upgrade complete at `date`"
