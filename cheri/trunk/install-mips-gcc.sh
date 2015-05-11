#-
# Copyright (c) 2014 Jonathan Woodruff
# Copyright (c) 2014 A. Theodore Markettos
# All rights reserved.
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

# Install the MIPS C compiler packages that are part of the Emdebian
# distribution.

echo "Adding Emdebian to your system repositories"
echo "deb http://www.emdebian.org/debian/ squeeze main" > /etc/apt/sources.list.d/emdebian.list
echo "deb http://ftp.us.debian.org/debian/ squeeze main" >> /etc/apt/sources.list.d/emdebian.list

echo "'Pinning' to minimize packages installed from Emdebian"
# Prevent the Debian 'squeeze' distro from overriding any system packages
cat << EOF > /etc/apt/preferences.d/emdebian
Package: *
Pin: release a=trusty
Pin-Priority: 700

Package: *
Pin: release a=precise
Pin-Priority: 660

Package: libgmp3c2
Pin: release a=squeeze
Pin-Priority: 600
EOF

echo "Installing Debian and Emdebian package signing keys"
apt-get install debian-archive-keyring emdebian-archive-keyring
echo "Updating package list"
apt-get update
echo "Installing Emdebian MIPS GCC"
apt-get install gcc-4.4-mips-linux-gnu

