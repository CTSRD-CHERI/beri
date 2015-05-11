# This script is designed to be sourced, it should not have a bangpath
#-
# Copyright (c) 2010-2011 Steven J. Murdoch
# Copyright (c) 2011 Wojciech A. Koszek
# Copyright (c) 2012 Robert N. M. Watson
# Copyright (c) 2012 Jonathan Woodruff
# Copyright (c) 2013 Simon W. Moore
# Copyright (c) 2013 Robert M. Norton
# Copyright (c) 2013 Colin Rothwell
# Copyright (c) 2013 Bjoern A. Zeeb
# Copyright (c) 2014 A. Theodore Markettos
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
#


# Example setup script for Bluespec and Quartus tools
# Each tool installs in its own directory structure
# This script configures necessary paths and license locations
# You will need to modify it to suit your local setup
# Save the resulting script as setup-local.sh in cheri/trunk directory


# Indicate the versions we're intending to use
export QUARTUS_VERSION=13v1
export BLUESPEC_VERSION=2014.05.C
# Comment this out if you don't intend to use Altera Quartus
QUARTUS_ENABLE=1

# Adjust these paths to suit your local installation
# We suggest installing your tools into a subdirectory based on their
# version number, so it is easy to alternate between different versions
export QUARTUS_INSTALL_VOLUME=/opt/quartus
export QUARTUS_ROOTDIR=$QUARTUS_INSTALL_VOLUME/$QUARTUS_VERSION
export BLUESPEC_INSTALL_VOLUME=/opt/bluespec
export BLUESPEC_ROOTDIR=$BLUESPEC_INSTALL_VOLUME/Bluespec-$BLUESPEC_VERSION

#
# Licensing arrangements come in two types: node-locked licenses tied to
# your particular machine, or floating licenses with an external license server.
#

# If you have a node-locked license, point this to your Bluespec license file
export BLUESPEC_LICENSE_FILE=$BLUESPEC_INSTALL_VOLUME/bluespec.lic

# If you have a floating license, you should have registered the host ID
# (MAC address) of the license server with Bluespec and configured FlexLM to run on
# that machine.  You will have edited the license file to contain:
# The hostname of the machine (for example, lmserv-bluespec.example.com)
# The port of the lmgrd daemon (for example, 27000)
#
# Uncomment and adjust this line to match your environment
#export BLUESPEC_LICENSE_FILE=27000@lmserv-bluespec.example.com

# Similarly, if you have a node-locked Altera license, point this to the file
export ALTERA_LICENSE_FILE=$QUARTUS_INSTALL_VOLUME/quartus.lic
# or point to your FlexLM license server for Altera
#export ALTERA_LICENSE_FILE=27012@lmserv-altera.example.com
# you can comment out both lines if you don't have an Altera license


# You should not need to modify below this point

export BLUESPEC=$BLUESPEC_ROOTDIR
export BLUESPECDIR=$BLUESPEC_ROOTDIR/lib

if [ -d $BLUESPEC/bin ] ; then
  export PATH=$PATH:$BLUESPEC/bin
fi

echo "Bluespec paths successfully configured for version $BLUESPEC_VERSION"

if [ "$QUARTUS_ENABLE"=="1" ] ; then

  export SOPC_KIT_NIOS2=$QUARTUS_ROOTDIR/nios2eds
  if [ -d $QUARTUS_ROOTDIR ] ; then
    export PATH=$PATH:$QUARTUS_ROOTDIR/bin
  fi

  if [ -d $SOPC_KIT_NIOS2 ] ; then
    export PATH=$PATH:$SOPC_KIT_NIOS2/bin
  fi

  # workaround a concurrency problem of multiple users running concurrent Qsys builds
  mkdir -p /tmp/$USER
  export TMP=/tmp/$USER
  export TEMP=/tmp/$USER

  export QUARTUS_64BIT=1
  export QUARTUS_BIT_TYPE="64"
  if [ -z "$LC_CTYPE" ] ; then
    #echo "LC_CTYPE not set - setting to " $LANG
    export LC_CTYPE=$LANG
  fi
  if [ -z "$LANGUAGE" ] ; then
    #echo "LANGUAGE not set - setting to " $LANG
    export LANGUAGE=$LANG
  fi

  echo "Quartus paths successfully configured for version $QUARTUS_VERSION"
fi
