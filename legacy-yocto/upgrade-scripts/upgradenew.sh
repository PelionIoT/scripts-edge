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

# upgradeMaster.sh
# Wipes the User partition
# Wipes the Upgrade partition
# upgrades the factory partition
# VERSION 2 (MARCH 2017)

#todo
#validate that it doesn't backwards upgrade the factory


#These are the defaults that are set in the int script anways.  To overide them, you can set them to something different

#wipes the factory partition (only use this in specail cases. 
# if we are upgrading the factory partition, it is automatically wiped),
#  if you specify this, and nothing else, you will brick your relay.
WIPETHEFACTORY=0
#upgrades the factory only if the factory differs in version number from the current factory partition. 
#We always wipe the factory clean and never copy over during an upgrade
UPGRADETHEFACTORYWHENNEWER=1
#upgrades the factory regardless of what is currently on the factory partition. 
FORCEUPGRADETHEFACTORY=0
#repartition the emmc to the new parition table (only during a factory upgrade, and only if its needed)
REPARTITIONEMMC=1
#Example:
#	UPGRADETHEFACTORY=0
#	FORCEUPGRADETHEFACTORY=0
#	REPARTITIONEMMC=1
#	Resut, nothing happens
#Example:
#	UPGRADETHEFACTORY=1
#	FORCEUPGRADETHEFACTORY=0
#	REPARTITIONEMMC=1
#	Resut, The drive will be repartitioned (if and only if) the desired partition size does not match the 
#	current partiion size, and only if the Upgrade is deemed necessary by having a newer factory avaiable than
#  	what is currnetly installed
#Example:
#	UPGRADETHEFACTORY=0
#	FORCEUPGRADETHEFACTORY=1
#	REPARTITIONEMMC=1
#	Resut, The drive will be repartitioned (if and only if) the desired partition size does not match the 
#	current partiion size, A new factory image is forced installed even
#wipes the upgrade partition (only use this in specail cases.  
#if we are upgrading the upgrade partition, it is automatically wiped)
#if you specifiy this, and nothing else, you will brick your relay
WIPETHEUPGRADE=0
#upgrades the upgrade only if the upgrade differs in version number for the current upgrade partition
#we alaways wipe the upgrade partition before installing.  never copy over. 
UPGRADETHEUPGRADEWHENNEWER=1
#upgrades the upgrade regarless of what is currently on the upgrade parition
FORCEUPGRADETHEUPGRADE=0
#wipes the user partition clean
#Note we don't "automatically" wipe the user, userdata, or boot partitions as those parititons hold userdata"
#if you want them wiped in the upgrade, you must call the following
WIPETHEUSER_PARTITION=0
#upgrades the user partition with user.tar.xz.  (an unforseen preventive condition)
#strategy is copyover unless WIPETHEUSER_PARTITION is set.
UPGRADETHEUSER_PARTITIONWHENNEWER=0
#forces the upgrade of the user partition. 
FORCEUPGRADETHEUSER_PARTITION=0
#wipes the userdata partition clean
#Note we don't "automatically" wipe the user, userdata, or boot partitions as those parititons hold userdata"
#if you want them wiped in the upgrade, you must call the following
WIPETHEUSERDATA=0
#upgrades the user partition with userdata.tar.xx.  (an unforseen preventive condition)
#strategy is copyover unless WIPETHEUSERDATA is set.
UPGRADETHEUSERDATAWHENNEWER=0
#forces the upgrade of the user partition. 
FORCEUPGRADETHEUSERDATA=0
#wipes the boot partition clean
#Note we don't "automatically" wipe the user, userdata, or boot partitions as those parititons hold userdata"
#if you want them wiped in the upgrade, you must call the following
WIPETHEBOOT=0
#upgrades the user partition with boot.tar.xz.  (an unforseen preventive condition)
#strategy is copyover unless WIPETHEBOOT is set.
UPGRADETHEBOOTWHENNEWER=1
#upgrades the boot whenever there is a file different in the upgrade
UPGRADEKERNELWHENDIFFERENT=1
#upgrades the kernel whenever there is file size difference in the kernel
UPGRADETHEBOOTWHENDIFFERENT=0
#forces the upgrade of the user partition. 
FORCEUPGRADETHEBOOT=0
#wipes the u-boot section clean
#Note we don't "automatically" wipe the u-boot.  This could be catestrophic unless you immedatly install a new-uboot
#Note we have tremendous success with just overwritting the uboot. so just do that usually
WIPETHEU_BOOT=0
#upgrades the uboot sector with the u-boot.bin located on the boot partitition
#strategy is copyover unless WIPETHEUBOOT is set. (Which happens to be exteremly dangerous)
UPGRADETHEU_BOOTWHENNEWER=1
#forces the upgrade of the uboot
FORCEUPGRADETHEU_BOOT=0
#Set the partition schema to be used.
PARTITIONSCHEMA=2
#if the partition schema does not match, the following flag will upgrade the partition schema, and will also 
#set the Factory Upgrade to force and Upgrade partition to force automatically because those partitions are wiped 
#during a re-schema
REPARTITIONEMMC=1



if [[ $master_initscript_version -gt 2 ]]; then
	UPGRADE
else
	echo "Installing new initscript"
	cd /
	mkdir /mnt/.boot/
	mount /dev/mmcblk0p1 /mnt/.boot/
	mount /dev/mmcblk0p5 /mnt/.overlay/user/
	mkdir /tmpfs
	mount -t tmpfs -o size=409600K,mode=700 tmpfs /tmpfs
	echo -e "UPDATER:\texpanding /mnt/.overlay/user/slash/upgrades/upgrade.tar.gz to /tmpfs"
	tar xzf /mnt/.overlay/user/slash/upgrades/upgrade.tar.gz -C /tmpfs
	umount /dev/mmcblk0p5
	cd /tmpfs
	ls -al /mnt/.boot/
	tar xJf boot.tar.xz -C /mnt/.boot/
	if [[ $? -eq 0 ]]; then
		success=1
		echo -e "UPDATER:\tBoot push succeeded"
	fi
	cd /
	ls -al /mnt/.boot/
	echo -e "UPGRADE_SCRIPT:\tinstalling the new uboot"
	dd if=/mnt/.boot/u-boot.bin of=/dev/mmcblk0 bs=1024 seek=8
	umount /dev/mmcblk0p1
	reboot -f
fi

