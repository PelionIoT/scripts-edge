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

echo -e "#!/bin/bash\nsleep 60\nreboot\n" > /tmp/rebooter.sh
chmod 777 /tmp/rebooter.sh
#the following line un-does the writing of the versions file in the overlay "user"
#We need info to perform correctly and this corrects the old way it used to work
rm -rf /mnt/.overlay/user/slash/wigwag/etc/versions.json
/tmp/rebooter.sh &

