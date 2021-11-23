# factoryupgrade.sh
# Factory 
# VERSION 6 (Oct 2016)

# Copyright (c) 2020, Arm Limited and affiliates.
# SPDX-License-Identifier: Apache-2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

color 0 0 0
sleep 1
color 1 0 0
sleep 1
color 0 1 0
sleep 1
color 0 0 1
sleep 1
color 0 1 1
mkfs.ext4 -F -i 4096 -L "factory" $dev_factory
mount $dev_factory $bbmp_factory
mkdir /tmpfs
mount -t tmpfs -o size=409600K,mode=700 tmpfs /tmpfs
echo "expanding $UGtarball to /tmpfs"
tar xzf $UGtarball -C /tmpfs
cd /tmpfs
echo "expanding factory.tar.xz to $bbmp_factory"
tar xJf factory.tar.xz -C $bbmp_factory/
if [[ $? -eq 0 ]]; then
        rm -rf $UGtarball
        rm -rf $UGscript
   echo "Upgrade Succeeded"
   #mkfs.ext4 -F -N 128000 -L "upgrade" $dev_upgrade
   mkfs.ext4 -F -i 4096 -L "upgrade" $dev_upgrade
fi
cd /
umount $dev_factory
echo "checking the filesystems $dev_factory $dev_upgrade"
e2fsck -y $dev_factory
e2fsck -y $dev_upgrade
color 0 0 0

