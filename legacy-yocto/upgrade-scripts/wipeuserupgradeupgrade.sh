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

# wipeuserupgradeupdate.sh
# Upgrade Wipe
# VERSION 6 (Oct 2016)
color 0 0 0
sleep 1
color 1 0 0
sleep 1
color 0 1 0
sleep 1
color 0 0 1
sleep 1
color 0 1 1
mkfs.ext4 -F -L "upgrades" $dev_upgrade
mount -rw $dev_upgrade $bbmp_upgrade
tar -xzf $UGtarball -C $bbmp_upgrade/
if [[ $? -eq 0 ]]; then
        rm -rf $UGtarball
        rm -rf $UGscript
   echo "Upgrade Succeeded"
fi
cd /
umount $dev_upgrade
e2fsck -y $dev_upgrade
#portion that erases the userdata db and the user
umount $dev_userdata
echo "formating userdata"
mkfs.ext4 -F -i 4096 -L "userdata" $dev_userdata
echo "checking the filesystems $dev_userdata"
e2fsck -y $dev_userdata
echo "cleaning up user"
rm -rf $bbmp_user_slash/*
rm -rf $bbmp_user_slash/.*
rm -rf $bbmp_user_slash/*.*
