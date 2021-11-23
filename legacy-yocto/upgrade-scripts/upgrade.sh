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
# VERSION 2 (January 2017)

#upgrades the factory only if the factory differs in version number from the current factory partition
UPGRADETHEFACTORY=1
#upgrades the factory regardless of what is currently on the factory partition.  ALSO SET the regular upgrade if you want it to work
FORCEUPGRADETHEFACTORY=0
#upgrades the upgrade only if the upgrade differs in version number for the current upgrade partition
UPGRADETHEUPGRADE=1
#upgrades the upgrade regarless of what is currently on the upgrade parition
FORCEUPGRADETHEUPGRADE=0
#wipes the user partition clean
WIPETHEUSER_PARTITION=0
#wipes the user database clean
WIPETHEUSERDB=0
#wipes the upgrade parititon (only use this in specail cases.  if we are upgrading the upgrade partition, it is automatically wiped)
WIPETHEUPGRADE=0
#wipes the factory parititon (only use this in specail cases.  if we are upgrading the factory partition, it is automatically wiped)
WIPETHEFACTORY=0


echo -e "UPGRADE THE FACTORY?\t\t\t $UPGRADETHEFACTORY"
echo -e "FORCE UPGRADE FACTORY?\t\t\t $FORCEUPGRADETHEFACTORY"
echo -e "UPGRADE THE UPGRADE?\t\t\t $UPGRADETHEUPGRADE"
echo -e "FORCE UPGRADE THE UPGRADE?\t\t $FORCEUPGRADETHEUPGRADE"
echo -e "WIPE THE USER PARTITION?\t\t $WIPETHEUSER_PARTITION"
echo -e "WIPE THE USERDB?\t\t\t $WIPETHEUSERDB"
echo -e "WIPE THE FACTORY?\t\t\t $WIPETHEFACTORY"
echo -e "WIPE THE UPGRADE?\t\t\t $WIPETHEUPGRADE"




color 0 0 0
sleep 1
color 1 0 0
sleep 1
color 0 1 0
sleep 1
color 0 0 1
sleep 1
color 0 1 1

success=0


if [[ "$WIPETHEFACTORY" -eq 1 ]]; then
	#WIPES the FACTORY patititon by using mkfs
	echo -e "UPDATER:\terasing the factory partition"
	mkfs.ext4 -F -i 4096 -L "factory" $dev_factory
fi

if [[ "$FORCEUPGRADETHEFACTORY" -eq 0 ]]; then
	mount $dev_factory $bbmp_factory
	testfactorydiff=$(diff /mnt/.overlay/user/slash/upgrades/factoryversions.json /mnt/.overlay/factory/wigwag/etc/versions.json)
	if [[ $? -ne 0 ]]; then
		echo -e "UPDATER:\tdiff file does not exist: forcing upgrade factory"
		testupgradediff="just do it"
	fi
	umount $dev_factory
else
	echo -e "UPDATER:\tforcing upgrade factory called"
	testfactorydiff="just do it"
	UPGRADETHEFACTORY=1
fi

if [[ "$UPGRADETHEFACTORY" -eq 1 ]]; then
	if [ "$testfactorydiff" != "" ]; then
		#WIPES the FACTORY patititon by using mkfs
		echo -e "UPDATER:\terasing the factory partition"
		mkfs.ext4 -F -i 4096 -L "factory" $dev_factory
		#writes the factory.tar.xz to the factory partition (upgrades it)
		mount $dev_factory $bbmp_factory
		mkdir /tmpfs
		mount -t tmpfs -o size=409600K,mode=700 tmpfs /tmpfs
		echo -e "UPDATER:\texpanding $UGtarball to /tmpfs"
		tar xzf $UGtarball -C /tmpfs
		cd /tmpfs
		echo -e "UPDATER:\tupgrading the factory parititon with factory.tar.xz to $bbmp_factory"
		tar xJf factory.tar.xz -C $bbmp_factory/
		if [[ $? -eq 0 ]]; then
			success=1
			echo -e "UPDATER:\tUpdate Factory partition succeeded"
		fi
		cd /
		umount $dev_factory
	else
		echo -e "UPDATER:\tskipped updating the factory partition.  Versions match."
		success=1
	fi
fi

if [[ "$WIPETHEUPGRADE" -eq 1 ]]; then
	umount $dev_upgrade
	echo -e "UPDATER:\terasing the upgrade partition"
	mkfs.ext4 -F -i 4096 -L "upgrade" $dev_upgrade
fi

if [[ "$FORCEUPGRADETHEUPGRADE" -eq 0 ]]; then
	mount $dev_upgrade $bbmp_upgrade
	testupgradediff=$(diff /mnt/.overlay/user/slash/upgrades/upgradeversions.json /mnt/.overlay/upgrade/wigwag/etc/versions.json)
	if [[ $? -ne 0 ]]; then
		echo -e "UPDATER:\tdiff file does not exist: forcing upgrade update"
		testupgradediff="just do it"
	fi
	umount $dev_upgrade
else
	echo -e "UPDATER:\tforcing upgrade update called"
	testupgradediff="just do it"
	UPGRADETHEUPGRADE=1
fi

if [[ "$UPGRADETHEUPGRADE" -eq 1 ]]; then
	if [ "$testupgradediff" != "" ]; then
		umount $dev_upgrade
		echo -e "UPDATER:\terasing the upgrade partition"
		mkfs.ext4 -F -i 4096 -L "upgrade" $dev_upgrade
		mount -rw $dev_upgrade $bbmp_upgrade
		if [[ ! -d /tmpfs ]]; then
			mkdir /tmpfs
			mount -t tmpfs -o size=409600K,mode=700 tmpfs /tmpfs
			echo -e "UPDATER:\texpanding $UGtarball to /tmpfs"
			tar xzf $UGtarball -C /tmpfs	
		fi
		cd /tmpfs
		echo -e "UPDATER:\tupgrading the upgrade parititon with upgrade.tar.xz to $bbmp_upgrade"
		tar xJf upgrade.tar.xz -C $bbmp_upgrade/
		if [[ $? -eq 0 ]]; then
			success=1
			echo -e "UPDATER:\tUpdate Upgrade partition succeeded"
		fi
		cd /
		umount $dev_upgrade
	else
		echo -e "UPDATER:\tskipped updating the upgrade partition.  Versions match."
		success=1
	fi
fi

if [[ "$WIPETHEUSERDB" -eq 1 ]]; then
	umount $dev_userdata
	echo -e "UPDATER:\tformating userdata"
	mkfs.ext4 -F -i 4096 -L "userdata" $dev_userdata
	echo -e "UPDATER:\tchecking the filesystems $dev_userdata"
fi

umount $dev_user
mount -o rw $dev_user $bbmp_user
#WIPES the USER paritition by using rm's (you must do this last.  Remember /upgrades/ is on the user partition)
if [[ "$WIPETHEUSER_PARTITION" -eq 1 ]]; then
	echo -e "UPDATER:\terasing the user paritition data files up user"
	rm -rf $bbmp_user_slash/*
	rm -rf $bbmp_user_slash/.*
	rm -rf $bbmp_user_slash/*.*
fi
echo "Success was found: $success"
if [[ $success -eq 1 ]]; then
	rm -rf $UGtarball
	rm -rf $UGscript
	rm -rf $UGdir/factoryversions.json
	rm -rf $UGdir/upgradeversions.json
	echo -e "UPDATER:\tremoved all upgrade files"
	   #mkfs.ext4 -F -N 128000 -L "upgrade" $dev_upgrade
	fi


	echo -e "UPDATER:\te2fsck repair partitions $dev_factory $dev_upgrade $dev_userdata"
	e2fsck -y $dev_factory
	e2fsck -y $dev_upgrade
	e2fsck -y $dev_userdata

	reboot -f 
