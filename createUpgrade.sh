#!/bin/bash

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
    sudo mount -o loop,ro,offset=$((512*${start_sector})),sizelimit=$((512*${sector_count})) -t ${partition_type} "${wic_file}" "${mount_point}"
}

# Convenience/symmetry function
# Params:
#    1 - mount point (or /dev name)
umount_wic_partition() {
    blab Umounting "$1"
    sudo umount "$1"
}

# Look up partition name for a given number, according to our standard partitioning scheme
# Params:
#    1 - partition number
partition_name() {
    case "$1" in
        1) echo "boot";;
        2) echo "factory";;
        3) echo "upgrade";;
        4) echo "extended";;
        5) echo "user";;
        6) echo "userdata";;
        *) echo "$1"; echo >&2 "Unsupported partition number: $1";;
    esac
}

# Look up tarball name for a given partition number
# Params:
#    1 - partition number
tarball_name() {
    case "$1" in
        1) echo "boot";;
        2) echo "upgrade";;
        5) echo "user";;
        6) echo "userdata";;
        *) echo "$1"; echo >&2 "Bad tarball partition: $1";;
    esac
}

# Generate diff and create tarball (and its md5) between one partition of two given images
# Params:
#    1 - old image file name
#    2 - new image file name
#    3 - partition number
#    4 - [optional] temporary directory for packing/unpacking files [default: TMPDIR, fallback current directory]
# Assumptions: workdir/pack exists and is used for the output tarball+md5
diff_partition() {
    local wic_old="$1"
    local wic_new="$2"
    local partition="$3"
    local workdir="${4:-${TMPDIR:-$(pwd)}}"
    local tarname="$(tarball_name $partition)"

    blab "===> Diffing partition $partition"

    mount_wic_partition "$wic_old" "$partition" "$workdir/old" || return 1
    mount_wic_partition "$wic_new" "$partition" "$workdir/new" || {
        umount_wic_partition "$workdir/old"
        return 2
    }

    blab Running rsync
    # TODO: this does not handle removed files (i.e. old files that aren't supposed to be there anymore will not be marked in any way)
    sudo rsync -rclkWpg "--compare-dest=$workdir/old/" "$workdir/new/" "$workdir/diff"

    # TODO: the versions mechanism is wedged in the diff process. Clean up by separating into its own function (though that will require a remount).
    [ $partition -eq 2 -a -f $workdir/new/wigwag/etc/versions.json ] && \
        cp "$workdir/new/wigwag/etc/versions.json" "$workdir/field/upgradeversions.json"

    umount_wic_partition "$workdir/old"
    umount_wic_partition "$workdir/new"

    [ $partition -eq 1 ] && {
        # The fancy new (secure) u-boot gets written directly to offset 1M (after the partition table)
        # instead of being a regular file in the boot partition. The magic max length of 1920k was
        # passed on as tribal knowledge; as far as the .wks config goes, the available space is 3M.
        # If the new u-boot is different, we'll store it in the boot upgrade tarball as fip2.bin
        blab Checking secure u-boot
        dd "if=$wic_old" "of=$workdir/diff/fip2.old" bs=1024 skip=1024 count=1920
        dd "if=$wic_new" "of=$workdir/diff/fip2.bin" bs=1024 skip=1024 count=1920
        diff -q "$workdir/diff/fip2.old" "$workdir/diff/fip2.bin" >/dev/null && rm -f "$workdir/diff/fip2.bin"
        rm -f "$workdir/diff/fip2.old"
    }

    blab Processing blacklist
    # Remove files in blacklist if there is one
    [ -f upgradeBlacklist.txt ] && grep -v '^#\|^$' upgradeBlacklist.txt | while read f; do
        # TODO: add safety check to prevent the blacklist from accidentally escaping workdir
        rm -f "$workdir/diff/$f" 2>/dev/null
    done

    blab Packing diff into "$workdir/pack/$tarname.tar.xz"
    # TODO: Why are we using both .gz and .xz? Settle for one of them (hint: .xz is suboptimal for tight embedded systems, because it requires large amounts of RAM)
    tar -cJ${TARVFLAG}f "$workdir/pack/$tarname.tar.xz" -C "$workdir/diff" .
    md5sum "$workdir/pack/$tarname.tar.xz" > "$workdir/pack/$tarname.tar.xz.md5"

    rm -rf "$workdir/old" "$workdir/new" "$workdir/diff"
}

# Package the difference into the correct tarball schema
# Params:
#    1 - [optional] temporary directory for packing/unpacking files [default: TMPDIR, fallback current directory]
#    2 - [optional] tag
# Assumptions: workdir/pack exists and is the location of individual partition diffs (tarball+md5 each)
packageDiff() {
    local workdir="${1:-${TMPDIR:-$(pwd)}}"
    local signKey="$2"
    local tag="$3"

    blab "===> Packing everything up"
    blab "Creating $workdir/field/upgrade.tar.gz"
    tar -cz${TARVFLAG}f "$workdir/field/upgrade.tar.gz" -C "$workdir/pack" .
    md5sum "$workdir/field/upgrade.tar.gz" > "$workdir/config/upgrade.tar.gz.md5"
    blab "Creating $workdir/field/upgrade-config.tar.gz"
    tar -cz${TARVFLAG}f "$workdir/field/upgrade-config.tar.gz" -C "$workdir/config" .
    blab "Signing upgrade tarballs"
    openssl dgst -sha256 -sign "${signKey}" -out "$workdir/field/upgrade.tar.gz.sig" "$workdir/field/upgrade.tar.gz" 
    openssl dgst -sha256 -sign "${signKey}" -out "$workdir/field/upgrade-config.tar.gz.sig" "$workdir/field/upgrade-config.tar.gz" 

    outtar="field-upgradeupdate.tar.gz"
    [ -n "${tag}" ] && outtar="${tag}-${outtar}"
    blab "Creating $(pwd)/$outtar"
    tar -cz${TARVFLAG}f "$outtar" -C "$workdir/field" .
    echo "Field upgrade output to $outtar"
}

# Setup temporary working space
# Params:
#    1 - signCert: certificate file staged here for later packaging
#
setupTemp() {
    # TODO: make TMPDIR a parameter, not a global variable
    TMPDIR=$(mktemp -d)
    local signCert="$1"

    blab "===> Setting up workdir in $TMPDIR"
    mkdir -p $TMPDIR/pack
    mkdir -p $TMPDIR/field
    mkdir -p $TMPDIR/config
    touch $TMPDIR/config/upgradeversions.json
    cp upgrade-scripts/upgrade.sh $TMPDIR/config
    cp upgrade-scripts/install.sh $TMPDIR/config
    cp upgrade-scripts/post-install.sh $TMPDIR/config
    cp "$signCert" $TMPDIR/field/upgrade.cert
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
#     3 - upgradeCert: certificate to be packaged with the upgrade and used to validate signatures
#     4 - upgradeKey:  private key corresponding to upgradeCert used by this script to genrate signatures
#     5 - tag:         optional text tag to be prepended to the output tarball
# Output:
#     <tag>-field-upgradeupdate.tar.gz
main() {
    local oldwic="$1"
    local newwic="$2"
    local upgradeCert="$3"
    local upgradeKey="$4"
    local tag="$5"
    local success=1

    [ -f "${oldwic}" ] && [ -f "${newwic}" ] && [ -f "${upgradeCert}" ] && [ -f "${upgradeKey}" ] || {
        echo >&2 "Usage: sudo createUpgrade.sh [--verbose] <old_wic_file> <new_wic_file> <upgrade_certificate> <upgrade_key> [upgrade_tag]"
	echo >&2 "    old_wic_file        - base image for upgrade"
	echo >&2 "    new_wic_file        - result image for upgrade"
	echo >&2 "    upgrade_certificate - certificate packaged with upgrade used to verify signatures"
	echo >&2 "    upgrade_key         - private key for upgrade_certificate used to generate signatures"
	echo >&2 "    upgrade_tag         - optional text string prepended to output tarball filename"
        return 1
    }

    # Make sure we have all the binaries we need; gzcat can be substituted
    type gzcat >/dev/null 2>&1 || gzcat() { gzip -c -d -f "$@"; }
    require_binaries gzip gzcat xz tar openssl md5sum grep rsync mount umount fdisk sfdisk || return 2

    [ -f upgrade-scripts/upgrade.sh ] || {
        echo >&2 "Please run within a checkout of scripts-pelion-os-edge repo."
        echo >&2 "./upgrade-scripts/upgrade.sh needs to exist in the current directory"
        return 2
    }

    # TODO: Right now, commands run as sudo (e.g. rsync) create files with root as owner, thus requiring pretty much the entire remaining script to be run as root as well. Fix it.
    # Ensure we are running as root
    [ $(id -u) -ne 0 ] && {
        echo >&2 "Please run as root"
        return 3
    }

    # Create tmp working space
    setupTemp "$upgradeCert"

    # If input wic files are gzipped, gunzip them otherwise copy them as is
    gzcat -f "$oldwic" > ${TMPDIR}/old_wic
    gzcat -f "$newwic" > ${TMPDIR}/new_wic

    # Diff each partition - not all at the same time, to minimize usage of the loopback devices
    for p in 1 2 5 6; do
        diff_partition ${TMPDIR}/old_wic ${TMPDIR}/new_wic $p || {
            success=0
            break
        }
    done

    # Package diffs
    [ $success -eq 1 ] && packageDiff "$TMPDIR" "$upgradeKey" "$tag"

    # Cleanup the temp working space
    cleanup
}

[ "$1" = "--verbose" ] && VERBOSE=1 && TARVFLAG=v && shift
main "$@"
