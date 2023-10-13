#!/bin/bash

#constants
EXTEND_DEVICE_PARAM="extend.device"
EXTEND_SIZE_PARAM="extend.size"
BOOT_PARTITION_FLAG="boot"

#variables
EXTEND_DEVICE=""
EXTEND_SIZE=""
BOOT_PARTITION_NUMBER=""


get_boot_partition_number() {
    BOOT_PARTITION_NUMBER=$(/usr/sbin/parted -m "$EXTEND_DEVICE" print  | /usr/bin/sed -n '/^[0-9]*:/p'| /usr/bin/sed -n '/'"$BOOT_PARTITION_FLAG"'/p'| /usr/bin/awk -F':' '{print $1}')
    status=$?
    if [[ $status -ne 0 ]]; then
        echo "Unable to identify boot partition number for '$EXTEND_DEVICE': $BOOT_PARTITION_NUMBER" >/dev/kmsg
        exit 1
    fi
    if [[ "$(/usr/bin/wc -l <<<"$BOOT_PARTITION_NUMBER")" -ne "1" ]]; then
        echo "Found multiple partitions with the boot flag enabled for device $EXTEND_DEVICE" >/dev/kmsg
        exit 1
    fi
    if ! [[ "$BOOT_PARTITION_NUMBER" == +([[:digit:]]) ]]; then
        echo "Invalid boot partition number '$BOOT_PARTITION_NUMBER'" >/dev/kmsg
        exit 1
    fi
}

disable_lvm_lock(){
    tmpfile=$(/usr/bin/mktemp)
    sed -e 's/\(^[[:space:]]*\)locking_type[[:space:]]*=[[:space:]]*[[:digit:]]/\1locking_type = 1/' /etc/lvm/lvm.conf >"$tmpfile"
    status=$?
    if [[ status -ne 0 ]]; then
     echo "Failed to disable lvm lock: $status" >/dev/kmsg
     exit 1
    fi
    # replace lvm.conf. There is no need to keep a backup since it's an ephemeral file, we are not replacing the original in the initramfs image file
    mv "$tmpfile" /etc/lvm/lvm.conf
}

parse_kernelops(){
    IFS=' ' read -ra array <<<"$(/usr/bin/cat /proc/cmdline)"
    for kv in "${array[@]}"; do
        if [[ "$kv" =~ ^"$EXTEND_DEVICE_PARAM"=.* ]] && [[ -z "$EXTEND_DEVICE" ]]; then
            EXTEND_DEVICE=${kv/$EXTEND_DEVICE_PARAM=/}
        fi
        if [[ "$kv" =~ ^"$EXTEND_SIZE_PARAM"=.* ]] && [[ -z "$EXTEND_SIZE" ]]; then
            EXTEND_SIZE=${kv/$EXTEND_SIZE_PARAM=/}
        fi
    done

    if [[ -z "$EXTEND_DEVICE" ]] && [[ -z "$EXTEND_SIZE" ]]; then
        echo "Unable to find required parameters $EXTEND_DEVICE_PARAM and $EXTEND_SIZE_PARAM in cmdline: ${array[*]}" >/dev/kmsg
        exit 1
    fi
}

main() {

    name=$(basename "$0")
    start=$(/usr/bin/date +%s)
    parse_kernelops
    get_boot_partition_number
    disable_lvm_lock
    # run extend.sh to increase boot partition and file system size
    ret=$(sh /usr/bin/extend.sh "$EXTEND_DEVICE" "$EXTEND_SIZE")
    status=$?
    end=$(/usr/bin/date +%s)
    # write the log file
    if [[ $status -eq 0 ]]; then
        echo "[$name] Boot partition $EXTEND_DEVICE$BOOT_PARTITION_NUMBER successfully extended by $EXTEND_SIZE ("$((end-start))" seconds) " >/dev/kmsg
    else
        echo "[$name] Failed to extend boot partition: $ret ("$((end-start))" seconds)" >/dev/kmsg
    fi
}

main "$0"