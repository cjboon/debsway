#!/bin/sh
# partman/early_command for debsway's install ISO (prep/make-install-iso.sh):
# runs inside the Debian installer just before partitioning, when the disks
# are known. It never erases anything itself; it only answers "which disk".
#
# The installer's own medium (the USB stick or DVD it runs from, mounted on
# /cdrom) is left out. If exactly one disk is left, that disk is chosen, and
# the boot loader goes on it too. If there are none or several, nothing is
# chosen and the installer asks. Either way the installer then asks once more
# before it writes anything ("Write the changes to disks?"), naming the disk.
# (DEBSWAY_MOUNTS, DEBSWAY_LIST and DEBSWAY_SET are for tests.)

MOUNTS=${DEBSWAY_MOUNTS:-/proc/mounts}
LIST=${DEBSWAY_LIST:-list-devices}
SET=${DEBSWAY_SET:-debconf-set}

# whole_disk DEVICE: /dev/sdb1 -> /dev/sdb, /dev/nvme0n1p2 -> /dev/nvme0n1,
# /dev/mmcblk0p1 -> /dev/mmcblk0, /dev/sdb -> /dev/sdb
whole_disk() {
    case $1 in
        /dev/nvme*p[0-9]* | /dev/mmcblk*p[0-9]*) echo "${1%p[0-9]*}" ;;
        /dev/nvme* | /dev/mmcblk*) echo "$1" ;;
        *) echo "$1" | sed 's/[0-9]*$//' ;;
    esac
}

medium=$(awk '$2 == "/cdrom" { print $1; exit }' "$MOUNTS" 2>/dev/null)
[ -z "$medium" ] || medium=$(whole_disk "$medium")

candidates=$($LIST disk 2>/dev/null | sed '/^[[:space:]]*$/d' | sort -u | while read -r d; do
    [ "$d" = "$medium" ] || echo "$d"
done)
count=$(printf '%s\n' "$candidates" | sed '/^$/d' | wc -l | tr -d ' ')

if [ "$count" = 1 ]; then
    $SET partman-auto/disk "$candidates"
    $SET grub-installer/bootdev "$candidates"
    logger -t debsway "installing on $candidates (the installer's own medium: ${medium:-none})" 2>/dev/null || true
else
    logger -t debsway "$count disks besides the installer's own medium: the installer asks which" 2>/dev/null || true
fi
exit 0
