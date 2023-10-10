#!/bin/bash

#constants
EXTEND_DEVICE_PARAM="extend.device"
EXTEND_SIZE_PARAM="extend.size"
BOOT_PARTITION_FLAG="boot"

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

function disable_lvm_lock(){
    tmpfile=$(/usr/bin/mktemp)
    sed -e 's/\(^[[:space:]]*\)locking_type[[:space:]]*=[[:space:]]*[[:digit:]]/\1locking_type = 1/' /etc/lvm/lvm.conf >"$tmpfile"
    status=$?
    if [[ status -ne 0 ]]; then
     echo "Failed to disable lvm lock: $status"
     return $status
    fi
    # replace lvm.conf. There is no need to keep a backup since it's an ephemeral file, we are not replacing the original in the initramfs image file
    mv "$tmpfile" /etc/lvm/lvm.conf
    return $status
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
        return 1
    fi
    return 0
}

function main() {
    current_dir=$(dirname "$0")
    start=$(/usr/bin/date +%s)
    ret=$(parse_kernelops)
    status=$?
    if [[ status -eq 0 ]]; then
        ret=$(disable_lvm_lock)
        status=$?
        if [[ status -eq 0 ]]; then
            # run extend.sh to increase boot partition and file system size
            ret=$("$current_dir"/extend.sh "$EXTEND_DEVICE" "$EXTEND_SIZE")
            status=$?
        fi
    fi
    end=$(/usr/bin/date +%s)
    # write the log file
    if [[ $status -eq 0 ]]; then
        echo "[$(basename "$0")] Boot partition $EXTEND_DEVICE$BOOT_PARTITION_NUMBER successfully extended by $EXTEND_SIZE ("$((end-start))" seconds) " >/dev/kmsg
    else
        echo "[$(basename "$0")] Failed to extend boot partition: $ret ("$((end-start))" seconds)" >/dev/kmsg
    fi
}

main "$0"