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

FROM ubuntu:20.10

RUN apt-get update && apt-get install locales \
    && dpkg-reconfigure locales \
    && locale-gen en_US.UTF-8 \
    && update-locale LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8

RUN apt-get update && apt-get install -y --no-install-recommends \
		python3 \
		python3-pip \
		python3-pexpect \
        python3-setuptools

RUN apt-get update && apt-get install -y \
        fdisk

RUN apt-get update && apt-get install -y --no-install-recommends \
        sudo \
        coreutils \
        gzip \
        tar \
        xz-utils \
        rsync \
        ostree

ENV LANG en_US.UTF-8

# Scripts used to build ostree static delta
COPY Docker/entrypoint.sh /usr/local/bin/entrypoint.sh

# Use the 'exec' form of ENTRYPOINT to ensure that docker run
# invocation arguments are appended to the command line.
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
