#!/bin/sh
#-
# Copyright (c) 2013 SRI International
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

DIR0=$(dirname $(realpath $0))
NAME=$(basename $0)

MTREE_NAME=demo.mtree
MTREE_PATH=${DIR0}/${MTREE_NAME}

DEMODIR_IMGS="Canon-5DII-3816.png Canon-5DII-4717.png Canon-5DII-5487.png"
EXTRA_IMG_DIR="slides/briefing.cpt"

echo "#mtree 2.0" > ${MTREE_PATH}
(cd ${DIR0}; find . -type d) | sed  -e 's#^\.#./demo#' \
    -e 's/$/ type=dir uname=root gname=wheel mode=0755/' >> ${MTREE_PATH}
(cd ${DIR0}; find . -type f \! -name ${NAME} -a \! -name demo.mtree) | \
    awk '{
	printf("%s type=file uname=root gname=wheel mode=0444 contents=%s\n",
	    $0, $0)
    }' | sed -e 's#^\.#./demo#' >> ${MTREE_PATH}

# XXX: these were hardlinks in the old world order, but there's no way to
# express that in current mtree manifests.
for dir in bad good; do
	for file in ${DEMODIR_IMGS}; do
		echo "./demo/${dir}/${file#Canon-5DII-} type=link" \
		    "uname=root gname=wheel mode=755" \
		    "link=/usr/share/images/${file}"
	done
	for file in `ls ${DIR0}/${EXTRA_IMG_DIR}/`; do
		echo "./demo/${dir}/$file type=link" \
		    "uname=root gname=wheel mode=755" \
		    "link=/demo/${EXTRA_IMG_DIR}/${file}"
	done
done >> ${MTREE_PATH}
