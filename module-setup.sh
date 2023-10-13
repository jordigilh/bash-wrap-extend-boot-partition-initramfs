#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

check(){
    return 0
}

install() {
    inst_multiple -o /usr/sbin/parted /usr/bin/mktemp /usr/bin/wc /usr/bin/date /usr/bin/sed /usr/bin/awk /usr/bin/basename /usr/sbin/resize2fs /usr/sbin/tune2fs /usr/sbin/partprobe /usr/bin/numfmt /usr/sbin/lvm /usr/bin/lsblk /usr/sbin/e2fsck /usr/sbin/fdisk /usr/bin/findmnt /usr/bin/tail
    inst_hook pre-mount 99 "$moddir/extend-boot-partition.sh"
    inst_binary "$moddir/sfdisk.static" "/usr/sbin/sfdisk"
    inst_simple "$moddir/extend.sh" "/usr/bin/extend.sh"
}