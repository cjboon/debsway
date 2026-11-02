#!/bin/bash
# The usb command: USB sticks mounted as you, by udisks2, never as root (with
# sudo mount, a FAT or exFAT stick's files are all root's, and you can't
# write to it). Mounted nosuid,nodev,noexec; FAT, exFAT and NTFS readable by
# you alone. polkitd (from network-manager.sh) lets you mount without sudo.
# Nothing mounts by itself: that is extras/udiskie.sh.
# Usage: bash usb.sh [--remove]
# status: bin:usb
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_bin usb
    apt_purge udisks2
    exit
fi

say "The usb command (udisks2)"
apt_install udisks2 polkitd
install_bin usb
note "usb lists your sticks; usb mount, usb unmount (then pull it out)."
