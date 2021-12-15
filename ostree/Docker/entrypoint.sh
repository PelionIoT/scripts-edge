#!/bin/bash

# Copyright (c) 2021, Pelion Limited and affiliates.
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

set -u

## UID/GID Management

# We need to manage uid/gid inside a container because the workspace
# VOLUME and the ssh agent authentication socket are shared between
# inside and outside.  We explicit capture the users uid and gid at
# 'docker run' and arrange for an entrypoint to create the necessary
# user on the fly.

# We need a username, but it doesn't matter what the name is, we only
# care that uid/gid are anchored correctly.

username="user"

# These environment variables are typically set by
# docker run -e LOCAL_UID=$(id -u) -e LOCAL_GID=$(id -g)

LOCAL_UID=${LOCAL_UID:-9001}
LOCAL_GID=${LOCAL_GID:-9001}

if groupadd -g "$LOCAL_GID" "$username"; then
   _=
else
  # We are about to test the exit code of groupadd, hence there can
  # be no statements inserted here before the if.

  # An exit code 4 indicates gid already exists, this is ok, we ignore
  # it, any other fail is a fail!
  if [ $? -ne 4 ]; then
    exit $?
  fi
fi

if useradd --shell /bin/bash -u "$LOCAL_UID" -g "$LOCAL_GID" -G sudo -c "" -m "$username"; then
  _=
else
  # We are about to test the exit code of useradd, hence there can
  # be no statements inserted here before the if.

  # An exit code 4 indicates uid already exists, this is ok, we ignore
  # it, any other fail is a fail!
  if [ $? -ne 4 ]; then
    exit $?
  fi
fi

export HOME=/home/"$username"

sed -i 's/%sudo  ALL=(ALL:ALL) ALL/%sudo ALL=(ALL:ALL) NOPASSWD:ALL/' /etc/sudoers

"$@"

