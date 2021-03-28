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

execdir="$(readlink -e "$(dirname "$0")")"

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
    sudo mount -o loop,rw,offset=$((512*${start_sector})),sizelimit=$((512*${sector_count})) -t ${partition_type} "${wic_file}" "${mount_point}"
}

# Convenience/symmetry function
# Params:
#    1 - mount point (or /dev name)
umount_wic_partition() {
    blab Umounting "$1"
    sudo umount "$1"
}

# Generate diff and create tarball (and its md5) between one partition of two given images
# Params:
#    1 - old image file name
#    2 - new image file name
#    3 - partition number
#    4 - [optional] temporary directory for packing/unpacking files [default: TMPDIR, fallback current directory]
# Assumptions: workdir/pack exists and is used for the output tarball+md5
ostree_diff_partition() {
    local wic_old="$1"
    local wic_new="$2"
    local partition="$3"
    local workdir="${4:-${TMPDIR:-$(pwd)}}"

    blab "===> Diffing partition $partition"

    mount_wic_partition "$wic_old" "$partition" "$workdir/old" || return 1
    mount_wic_partition "$wic_new" "$partition" "$workdir/new" || {
        umount_wic_partition "$workdir/old"
        return 2
    }

    blab Running OSTree difftool
    sudo ${execdir}/ostree-delta.py --repo "$workdir/old/ostree/repo" --output $workdir/delta --update_repo "$workdir/new/ostree/repo"

    umount_wic_partition "$workdir/old"
    umount_wic_partition "$workdir/new"

    rm -rf "$workdir/old" "$workdir/new" "$workdir/diff"
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
# Takes two input wic files and produces a tarball of their difference that can
# be used in the field upgrade process
# Params:
#     1 - oldwic: .wic file of the base or factory build to be upgraded
#     2 - newwic: .wic file of the new or upgrade build
#     3 - tag:    optional text tag to be prepended to the output tarball
# Output:
#     <tag>-field-upgradeupdate.tar.gz
main() {
    local oldwic="$1"
    local newwic="$2"
    local tag
    local success=1

    [[ -z "$3" ]] && tag="data.tar.gz" || tag="${3}"-data.tar.gz

    [ -f "${oldwic}" ] && [ -f "${newwic}" ] || {
        echo >&2 "Usage: sudo createUpgrade.sh [--verbose] <old_wic_file> <new_wic_file> [upgrade_tag]"
        echo >&2 "    old_wic_file        - base image for upgrade"
        echo >&2 "    new_wic_file        - result image for upgrade"
        echo >&2 "    upgrade_tag         - optional text string prepended to output tarball filename"
        return 1
    }

    # Make sure we have all the binaries we need; gzcat can be substituted
    type gzcat >/dev/null 2>&1 || gzcat() { gzip -c -d -f "$@"; }
    require_binaries gzip gzcat xz tar openssl md5sum grep rsync mount umount fdisk sfdisk || return 2

    # TODO: Right now, commands run as sudo (e.g. rsync) create files with root as owner, thus requiring pretty much the entire remaining script to be run as root as well. Fix it.
    # Ensure we are running as root
    [ $(id -u) -ne 0 ] && {
        echo >&2 "Please run as root"
        return 3
    }

    # Create tmp working space
    setupTemp

    md5sum $oldwic | awk -v srch="$oldwic" -v repl="$newwic" '{ sub(srch,repl,$0); print $0 }' > ${TMPDIR}/chksum.txt
    md5sum -c ${TMPDIR}/chksum.txt 2>/dev/null | grep -q "OK" && {
        echo >&2 "Base image and result image are the same! Please make sure they are different."
        return 4
    }

    # If input wic files are gzipped, gunzip them otherwise copy them as is
    gzcat -f "$oldwic" > ${TMPDIR}/old_wic
    gzcat -f "$newwic" > ${TMPDIR}/new_wic

    ostree_diff_partition ${TMPDIR}/old_wic ${TMPDIR}/new_wic 2 || {
            success=0
            break
        }

    mv ${TMPDIR}/delta/data.tar.gz ${tag}

    # Cleanup the temp working space
    cleanup
}

[ "$1" = "--verbose" ] && VERBOSE=1 && TARVFLAG=v && shift
main "$@"
