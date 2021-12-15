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

# TODO: add settings section to group all the hardcoded paths and values

# Output a message if verbose mode is on
blab() {
    [ "$VERBOSE" = 1 ] && echo "$@"
}

# Verify that given binaries are available
# Params: list of binaries, separated by space
# Returns the number of missing binaries (0=success)
require_binaries() {
    local retval=0
    for b in "$@"; do
        type "$b" >/dev/null 2>&1 || {
            echo >&2 "Please make sure binary $b is installed and available in the path."
            let retval++
        }
    done
    return $retval
}

# Mount a partition inside a .wic file (or any image file flashable with dd)
# Params:
#    1 - .wic file name (with path if needed)
#    2 - partition number [1-based] (leave blank to list partitions)
#    3 - mount point (full path to where the partition will be mounted; will be created if it doesn't exist)
#    4 - [optional] partition type (auto detected if not specified)
# To unmount: sudo umount /path/to/mount/point
mount_wic_partition() {
    local wic_file="$1"
    local partition_number="$2"
    local mount_point="$3"
    local partition_type="$4"
    local partition_info start_sector=0 sector_count=0

    [ -z "${wic_file}" ] && {
        echo >&2 "Usage: mount_wic_partition <wic_file> [<partition_number> <mount_point> [partition_type]]"
        return 2
    }

    [ -f "${wic_file}" ] || {
        echo >&2 "Can't access image file ${wic_file}"
        return 1
    }

    [ -z "${partition_number}" ] && {
        fdisk -lu "${wic_file}"
        return 0
    }

    [ -z "${mount_point}" ] && {
        echo >&2 "You must specify a mount point"
        return 3
    }

    partition_info=$(sfdisk -d "${wic_file}" | grep ': start=' | grep "${partition_number} : start" | head -1)
    [ -z "${partition_info}" ] && {
        echo >&2 "Partition ${partition_number} not found"
        return 4
    }

    start_sector=$(echo "${partition_info}" | cut -d , -f 1 | cut -d = -f 2)
    sector_count=$(echo "${partition_info}" | cut -d , -f 2 | cut -d = -f 2)
    [ -z "${partition_type}" ] && {
        partition_type=$(echo "${partition_info}" | cut -d , -f 3 | cut -d = -f 2)
        case "$partition_type" in
            c) partition_type=vfat;;
            83) partition_type=ext4;;
            *) echo "Unsupported partition type: ${partition_type}"
               echo "${partition_info}"
               return 5
        esac
    }

    mkdir -p "${mount_point}"
    blab Mounting wic partition "$partition_number" of "$wic_file" to "$mount_point"
    mount -o loop,rw,offset=$((512*start_sector)),sizelimit=$((512*sector_count)) -t ${partition_type} "${wic_file}" "${mount_point}"
}

# Convenience/symmetry function
# Params:
#    1 - mount point (or /dev name)
umount_wic_partition() {
    blab Umounting "$1"
    umount "$1"
}

# Setup temporary working space
#
setupTemp() {
    # TODO: make TMPDIR a parameter, not a global variable
    TMPDIR=$(mktemp -d)
    blab "===> Setting up workdir in $TMPDIR"
}

# Unmount partitions and remove temp files
# Params:
#    1 - [optional] temporary directory for packing/unpacking files [default: TMPDIR; for safety reasons, there is no fallback]
cleanup() {
    local workdir="${1:-${TMPDIR}}"
    blab "===> Cleaning up $workdir"
    # TODO: to avoid clobbering existing files if workdir was not a fresh directory: instead of rm -rf workdir, remove only pack/ and field/, then use rmdir
    [ -n "$workdir" ] && rm -rf "$workdir"
}

# Main function
# Takes a wic files and extracts the ostree repo
# Params:
#     1 - wic:         .wic file
#     2 - outputfile:  name of extracted repo folder
main() {
    local wic="$1"
    local output="$2"

    ([ -f "${wic}" ] && [ -n "${output}" ]) || {
        echo >&2 "Usage: sudo extractOSTreeRepo.sh [--verbose] <wic_file> <output>"
        echo >&2 "    wic_file        - .wic file containing the repo to extract"
        echo >&2 "    output          - name of extracted repo folder"
        return 1
    }

    # Ensure we are running as root so we can mount the partition
    [ "$(id -u)" -ne 0 ] && {
        echo >&2 "Please run as root"
        return 3
    }

    # Make sure we have all the binaries we need; gzcat can be substituted
    type gzcat >/dev/null 2>&1 || gzcat() { gzip -c -d -f "$@"; }
    require_binaries gzip gzcat xz tar openssl md5sum grep rsync mount umount fdisk sfdisk || return 2

    # Create tmp working space
    setupTemp

    # If input wic files are gzipped, gunzip them otherwise copy them as is
    gzcat -f "$wic" > "${TMPDIR}/wicfile"

    mount_wic_partition "${TMPDIR}/wicfile" 2 "${TMPDIR}/wic" || {
        rm -rf "${TMPDIR}/wic"
        # Cleanup the temp working space
        cleanup "${TMPDIR}"
        return 2
    }

    cp -R "${TMPDIR}/wic/ostree/repo"  "$output"

    umount_wic_partition "${TMPDIR}/wic"

    rm -rf "${TMPDIR}/wic"

    # Cleanup the temp working space
    cleanup "${TMPDIR}"
}

[ "$1" = "--verbose" ] && VERBOSE=1 && shift
main "$@"
