#!/bin/sh

# Copyright (c) 2014 Ed Maste
# All rights reserved.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-10-C-0237
# ("CTSRD"), as part of the DARPA CRASH research programme.
#
# This software was developed by SRI International and the University of
# Cambridge Computer Laboratory under DARPA/AFRL contract FA8750-11-C-0249
# ("MRC2"), as part of the DARPA MRC research programme.
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

usage()
{
    echo "usage: $0 <path to nios2-terminal-wrapped>"
    exit 1
}

# User confirmation to proceed with binary patch
# $1 - Version
# $2 - Patch function to execute (will be passed filename to patch)
confirm_patch()
{
    local base=${target%-wrapped}
    fasttarget=$base-fast

    cat <<EOF
Version: $1

WARNING: This will binary patch a copy of nios2-terminal, in order to
reduce a delay (usleep call) that causes significant slowdown to certain
berictl commands.  The original binary will not be changed.

EOF
    if [ -e $fasttarget ]; then
        echo "NOTE: patched binary already exists, and will be overwritten:"
        echo "$fasttarget"
    fi
    while true; do
        echo -n "Proceed with binary patch? [Y/n] "
        read r
        case "$r" in
        [yY]*|"")
            break
            ;;
        [nN]*)
            echo "Cancelled."
            exit 1
        esac
    done

    if [ "$base" != "$target" ]; then
        # Target matched expected filename *-wrapped
        if [ -e "$base" ]; then
            echo "Wrapper: $fasttarget"
            cp $base $fasttarget
        fi
        fasttarget=$fasttarget-wrapped
    fi
    cp "$target" "$fasttarget"
    $2 "$fasttarget"
    echo "Patched: $fasttarget"
}

patch_1()
{
    /usr/bin/printf '\x64\x00\x00\x00' | dd of="$1" bs=1 count=4 seek=9779 conv=notrunc 2>/dev/null
}

already_patched()
{
    echo "Version: $1, already patched."
    exit 0
}

target=$1
if [ -z "$target" ]; then
    target=$(which nios2-terminal-wrapped)
fi
if [ -z "$target" ]; then
    echo "nios2-terminal-wrapped not found in path"
    usage
fi
if [ ! -x "$target" ]; then
    echo "target binary $target not found or executable"
    usage
fi

for tool in sha256 sha256sum; do
    shatool=$(which $tool)
    if [ -x "$shatool" ]; then
        break
    fi
done
if [ -z "$shatool" ]; then
    echo "sha256 / sha256sum not found in path"
    exit 1
fi

shasum=$($shatool $target | sed 's/ .*$//')

echo " Target: $target"
echo " SHA256: $shasum"

case $shasum in
48346dd3088b594d04ddb405d5b123acfecebb554f7c9276c6f8c81b8fa2493a)
    confirm_patch 12.1 patch_1
    ;;
aef4f8ff9627ee95a5beba28a10897980b382ab564568ebfb8b643bc71f7943d)
    confirm_patch 13.0sp1 patch_1
    ;;
b36c55d69fae0ed3c0aaa3a110568608b7f6b48449bee0fbf71dcabfcf343938)
    confirm_patch 13.1 patch_1
    ;;
c87024acf574fe2c200d6ca61d7b1fde508e6763e1a8a19d9dfc94e45437f230)
    already_patched 12.1
    ;;
a69044c37ac5eb35313c08db14eb0f8588711eaf6249c8ad46b4a26ed4c93361)
    already_patched 13.0sp1
    ;;
d9b6e06f1955b8692bd1b303db31569aa94d6e15bd649ef855648e1f74aaac42)
    already_patched 13.1
    ;;
f76f9116fb7d9d57876ef4c0fa858132345c9ba9eddff80cd235a7a91e982241)
    echo "This is the wrapper shell script; this tool must be run on the binary."
    exit 1
    ;;
*)
    echo "No patch instructions for this binary."
    exit 1
    ;;
esac

exit 0
