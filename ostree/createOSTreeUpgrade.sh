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
main_part_num=0

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
    local partition_info start_sector=0 sector_count=0

    [ -z "${wic_file}" ] && {
        echo >&2 "Usage: mount_wic_partition <wic_file> [<partition_number> <mount_point>]"
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

    mkdir -p "${mount_point}"
    blab Mounting wic partition "$partition_number" of "$wic_file" to "$mount_point"
    sudo mount -o loop,rw,offset=$((512*start_sector)),sizelimit=$((512*sector_count)) "${wic_file}" "${mount_point}"
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
    sudo "${execdir}/ostree-delta.py" --repo "$workdir/old/ostree/repo" --output "$workdir/delta" --update_repo "$workdir/new/ostree/repo"

    umount_wic_partition "$workdir/old"
    umount_wic_partition "$workdir/new"

    rm -rf "$workdir/old" "$workdir/new" "$workdir/diff"
}

# Find number of main partition to diff
# Params: 
#    1 - old image file name
#    2 - new image file name
#    3 - [optional] temporary directory for packing/unpacking files [default: TMPDIR, fallback current directory]
# Assumptions: Main partition holds the ostree directory (while others don't)
ostree_find_main_partition_number() {
    local wic_old="$1"
    local wic_new="$2"
    local workdir="${3:-${TMPDIR:-$(pwd)}}"

    blab "===> Finding main partition number"

    main_part_num=1

    while : ; do
        blab "===> Trying partition $main_part_num"
        mount_wic_partition "$wic_new" "$main_part_num" "$workdir/new" || 
        {
            echo >&2 "Unable to find main partition"
            return 1
        }
        [ -d "$workdir/new/ostree" ] && break
        umount_wic_partition "$workdir/new"
        let main_part_num++
    done

    umount_wic_partition "$workdir/new"

    [ ! "$empty" ] && {
        mount_wic_partition "$wic_old" "$main_part_num" "$workdir/old" || return 1
        [ -d "$workdir/old/ostree" ] || {
            echo >&2 "old & new images have different partition schemes"
            return 2
        }
        umount_wic_partition "$workdir/old"
    }

    rm -rf "$workdir/old" "$workdir/new"
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
#     1 - oldwic:      .wic file of the base or factory build to be upgraded
#     2 - newwic:      .wic file of the new or upgrade build
#     3 - outputfile:  filename of the output tarball
create_delta_between_wic_files() {
    local oldwic="$1"
    local newwic="$2"
    local outputfile="$3"


    ([ -f "${oldwic}" ] && [ -f "${newwic}" ] && [ -n "${outputfile}" ]) || {
        echo >&2 ""
        [ -f "${oldwic}" ]     || echo >&2 "Error: Base image not found"
        [ -f "${newwic}" ]     || echo >&2 "Error: Upgrade image not found"
        [ -n "${outputfile}" ] || echo >&2 "Error: outputfile not provided"
        echo >&2 ""

        echo >&2 "Usage: sudo createOSTreeUpgrade.sh [--verbose] [--empty] <old_wic_file> <new_wic_file> <outputfile>"
        echo >&2 "    old_wic_file        - base image for upgrade"
        echo >&2 "    new_wic_file        - image to upgrade to"
        echo >&2 "    output_file         - filename of the output tarball"
        return 1
    }

    md5sum "$oldwic" | awk -v srch="$oldwic" -v repl="$newwic" '{ sub(srch,repl,$0); print $0 }' > "${TMPDIR}/chksum.txt"
    md5sum -c "${TMPDIR}/chksum.txt" 2>/dev/null | grep -q "OK" && {
        echo >&2 "Base image and result image are the same! Please make sure they are different."
        return 4
    }

    # If input wic files are gzipped, gunzip them otherwise copy them as is
    gzcat -f "$oldwic" > "${TMPDIR}/old_wic"
    gzcat -f "$newwic" > "${TMPDIR}/new_wic"

    ostree_find_main_partition_number "${TMPDIR}/old_wic" "${TMPDIR}/new_wic" || return 5

    ostree_diff_partition "${TMPDIR}/old_wic" "${TMPDIR}/new_wic" $main_part_num

    mv "${TMPDIR}/delta/data.tar.gz" "${outputfile}"

}

create_delta_from_scratch() {
    local wicfile="$1"
    local outputfile="$2"

    ([ -f "${wicfile}" ] && [ -n "${outputfile}" ]) || {
        echo >&2 ""
        [ -f "${wicfile}" ]     || echo >&2 "Error: Base image not found"
        [ -n "${outputfile}" ] || echo >&2 "Error: outputfile not provided"
        echo >&2 ""

        echo >&2 "Usage: sudo createOSTreeUpgrade.sh [--verbose] [--empty] <wic_file> <outputfile>"
        echo >&2 "    old_wic_file        - base image for upgrade"
        echo >&2 "    output_file         - filename of the output tarball"
        return 1
    }


    # If input wic files are gzipped, gunzip them otherwise copy them as is
    gzcat -f "$wicfile" > "${TMPDIR}/wicfile"

    ostree_find_main_partition_number "${TMPDIR}/wicfile" "${TMPDIR}/wicfile" || return 1

    blab "===> Diffing partition $partition"

    mount_wic_partition "${TMPDIR}/wicfile" $main_part_num "${TMPDIR}/wic" || return 2

    blab Running OSTree difftool
    sudo "${execdir}/ostree-delta.py" --repo "${TMPDIR}/wic/ostree/repo" --output "${TMPDIR}/delta" --empty

    umount_wic_partition "${TMPDIR}/wic"

    mv "${TMPDIR}/delta/data.tar.gz" "${outputfile}"
}

empty=0

args_list="empty,verbose"

args=$(getopt -o+ho:x -l $args_list -n "$(basename "$0")" -- "$@")
eval set -- "$args"

while [ $# -gt 0 ]; do
  if [ -n "${opt_prev:-}" ]; then
    eval "$opt_prev=\$1"
    opt_prev=
    shift 1
    continue
  elif [ -n "${opt_append:-}" ]; then
    eval "$opt_append=\"\${$opt_append:-} \$1\""
    opt_append=
    shift 1
    continue
  fi
  case $1 in
  --empty)
    empty=1
    ;;

  --verbose)
    VERBOSE=1
    ;;

  -x)
    set -x
    ;;

  --)
    shift
    break 2
    ;;
  esac
  shift 1
done

# Make sure we have all the binaries we need; gzcat can be substituted
type gzcat >/dev/null 2>&1 || gzcat() { gzip -c -d -f "$@"; }
require_binaries gzip gzcat xz tar openssl md5sum grep rsync mount umount fdisk sfdisk ostree || exit 2

# TODO: Right now, commands run as sudo (e.g. rsync) create files with root as owner, thus requiring pretty much the entire remaining script to be run as root as well. Fix it.
# Ensure we are running as root
[ "$(id -u)" -ne 0 ] && {
    echo >&2 "Please run as root"
    exit 3
}

# Create tmp working space
setupTemp

# Create the delta file.
if [ "$empty" = 1 ]; then
    create_delta_from_scratch "$@"
else
    create_delta_between_wic_files "$@"
fi

# Cleanup the temp working space
cleanup "${TMPDIR}"
