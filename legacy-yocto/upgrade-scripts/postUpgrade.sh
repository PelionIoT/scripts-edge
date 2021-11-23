#!/bin/bash

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

touch /tmp/upgrade.out

function grabOne(){
	a=$(i2cget -y 1 0x50 $1 b) 
	echo $a
}

function dec2hex() {
  echo "obase=16;ibase=10; $1" | bc
}

function hex2dec() {
	printf "%d\n" $1
}

function hex2ascii() {
	a=$(echo "$1" | sed s/0/\\\\/1)
	echo -en "$a"
	#echo $b
}


#output can be "ascii decimal hex hex-stripped"
function grabRange() {
	start=$1
	end=$2
	output=$3
	delimeter=$4
	RET=""
	for ((i=$start; i<=$end; i=i+1)); do
		h=$(printf "%#x\n" $i)
		hex=$(grabOne $h)
		if [[ $output == "decimal" ]]; then
			var=$(hex2dec $hex)
		elif [[ $output == "ascii" ]]; then
			var=$(hex2ascii $hex)
		elif [[ $output == "hex-stripped" ]]; then
			var=`expr "$hex" : '^0x\([0-9a-zA-Z]*\)'`		
		else
			var=$hex
		fi
		if [[ $RET == "" ]]; then
			 RET="$var"
		else
			RET+=$delimeter"$var"
		fi
	done
	echo $RET
}

function printEEPROM(){
    SN=$(grabRange 0 9 "ascii" "")
 	HWV=$(grabRange 10 14 "ascii" "")
	FWV=$(grabRange 15 19 "ascii" "")
	RC=$(grabRange 20 21 "ascii" "")
	YEAR=$(grabRange 22 22 "ascii" "")
	MONTH=$(grabRange 23 23 "ascii" "")
	BATCH=$(grabRange 24 24 "ascii" "")
	ETHERNETMAC=$(grabRange 25 30 "hex-stripped" ":")
	ETHERNETMACd=$(grabRange 25 30 "decimal" ",")
	SIXBMAC=$(grabRange 31 38 "hex-stripped" ":")
	SIXBMACd=$(grabRange 31 38 "decimal" ",")
	RELAYSECRET=$(grabRange 39 70 "ascii" "")
	PAIRINGCODE=$(grabRange 71 95 "ascii" "")
	LEDCONFIG=$(grabRange 96 97 "ascii" "")
	 echo "{\"batch\":\"$BATCH\",\"month\":\"$MONTH\",\"year\":\"$YEAR\",\"radioConfig\":\"$RC\",\"hardwareVersion\":\"$HWV\",\"firmwareVersion\":\"$FWV\",\"relayID\":\"$SN\",\"ethernetMAC\":[$ETHERNETMACd],\"sixBMAC\":[$SIXBMACd],\"relaySecret\":\"$RELAYSECRET\",\"pairingCode\":\"$PAIRINGCODE\",\"ledConfig\":\"$LEDCONFIG\"}"
}

printEEPROM
PAIRINGCODE=$(grabRange 71 95 "ascii" "")
RELAYSECRET=$(grabRange 39 70 "ascii" "")
if [ ! -e /mnt/.boot ] ; then
   mkdir /mnt/.boot
   mount /dev/mmcblk0p1  /mnt/.boot
fi

udhcpc eth0 >& /tmp/upgrade.out
cd /wigwag/wwrelay-utils/I2C
wget --user=${PAIRINGCODE} --password=${RELAYSECRET} https://prodcloud.wigwag.com/getID/${SN} >& /tmp/upgrade.out
node ./writeEEPROM.js --skipeeprom ${SN} >& /tmp/upgrade.out
