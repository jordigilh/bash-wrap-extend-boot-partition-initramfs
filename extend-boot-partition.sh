#!/bin/bash

#constants
EXTEND_DEVICE_PARAM="extend.device"
EXTEND_SIZE_PARAM="extend.size"
BOOT_PARTITION_FLAG="boot"
TARGET_MOUNT="/tmp/boot-"$RANDOM

#variables
EXTEND_DEVICE=
EXTEND_SIZE=
BOOT_PARTITION_NUMBER=


function get_boot_partition_number() {
    BOOT_PARTITION_NUMBER=$(/usr/sbin/parted -m "$EXTEND_DEVICE" print  | /usr/bin/sed -n '/^[0-9]*:/p'| /usr/bin/sed -n '/'"$BOOT_PARTITION_FLAG"'/p'| /usr/bin/awk -F':' '{print $1}')
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Unable to identify boot partition number for '$EXTEND_DEVICE': $BOOT_PARTITION_NUMBER"
        exit 1
    fi
    if [[ "$(/usr/bin/wc -l <<<"$BOOT_PARTITION_NUMBER")" -ne "1" ]]; then
        echo "Found multiple partitions with the boot flag enabled for device $EXTEND_DEVICE"
        exit 1
    fi
    if ! [[ "$BOOT_PARTITION_NUMBER" == +([[:digit:]]) ]]; then
        echo "Invalid boot partition number '$BOOT_PARTITION_NUMBER'"
        exit 1
    fi
}

function mount_boot_partition(){
    get_boot_partition_number
    /usr/bin/mkdir -p "$TARGET_MOUNT"
    /usr/bin/mount "$EXTEND_DEVICE""$BOOT_PARTITION_NUMBER" "$TARGET_MOUNT"
}

function parse_kernelops(){
    IFS=' ' read -ra array <<<"$(cat /proc/cmdline)"
    for kv in "${array[@]}"; do
        if [[ "$kv" =~ ^"$EXTEND_DEVICE_PARAM"=.* ]] && [[ -z "$EXTEND_DEVICE" ]]; then
            EXTEND_DEVICE=${kv/$EXTEND_DEVICE_PARAM=/}
        fi
        if [[ "$kv" =~ ^"$EXTEND_SIZE_PARAM"=.* ]] && [[ -z "$EXTEND_SIZE" ]]; then
            EXTEND_SIZE=${kv/$EXTEND_SIZE_PARAM=/}
        fi
    done

    if [[ -z "$EXTEND_DEVICE" ]] && [[ -z "$EXTEND_SIZE" ]]; then
        echo "Unable to find required parameters $EXTEND_DEVICE_PARAM and $EXTEND_SIZE_PARAM in cmdline: ${array[*]}"
        exit 1
    fi
}

function main() {
    current_dir=$(dirname "$0")
    start=$(/usr/bin/date +%s)
    parse_kernelops
    # run extend.sh to increase boot partition and file system size
    ret=$("$current_dir"/extend.sh "$EXTEND_DEVICE" "$EXTEND_SIZE")
    status=$?
    end=$(/usr/bin/date +%s)
    # mount the boot partition from the device
    mount_boot_partition
    # write the log file
    if [[ $status -eq 0 ]]; then
        echo "["$((end-start))" seconds] Boot partition successfully extended" >"$TARGET_MOUNT"/extend.log
    else
        echo "["$((end-start))" seconds] Boot partition failed to extend: $ret">"$TARGET_MOUNT"/extend.log
    fi
    # move old initramfs back
    kernel_version=$(/usr/bin/uname -r)
    old_initramfs=$(ls $TARGET_MOUNT/initramfs-"$kernel_version".img.old)
    if [[ -n "$old_initramfs" ]]; then
        mv -f "$old_initramfs" "${old_initramfs/.old/}"
    fi
    # reboot
    /usr/sbin/reboot
}

main "$0"