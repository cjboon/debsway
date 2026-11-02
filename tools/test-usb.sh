#!/bin/bash
# Checks bin/usb with pretend lsblk, findmnt, udisksctl and sudo (each logs
# what it is asked, nothing is mounted): sticks are found and the computer's
# own disk isn't; FAT and exFAT are mounted as you, yours alone, ext4 without
# the FAT options; a stick mounted by root is offered a mount as you (and
# left alone on no); an encrypted one is unlocked first and locked after;
# unmount switches the drive off; a disk mounted at / is never touched.
# Run by test.sh, or:  bash tools/test-usb.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

mkdir -p "$T/fake"
printf '#!/bin/sh\ncat "%s/lsblk.out"\n' "$T" >"$T/fake/lsblk"
printf '#!/bin/sh\ncat "%s/findmnt.out" 2>/dev/null\n' "$T" >"$T/fake/findmnt"
cat >"$T/fake/udisksctl" <<PRETEND
#!/bin/sh
echo "udisksctl \$*" >>"$T/calls"
case "\$1" in
    mount) echo "Mounted \$3 at /media/me/STICK" ;;
    unlock) echo "Unlocked \$3 as /dev/dm-3."; cat "$T/lsblk.unlocked" >"$T/lsblk.out" ;;
esac
PRETEND
printf '#!/bin/sh\necho "sudo $*" >>"%s/calls"\n' "$T" >"$T/fake/sudo"
chmod +x "$T/fake/"*
ME=$(id -u)
nvme='PATH="/dev/nvme0n1" TYPE="disk" FSTYPE="" SIZE="477G" PKNAME="" MOUNTPOINT="" LABEL="" HOTPLUG="0" RM="0" TRAN="nvme"
PATH="/dev/nvme0n1p2" TYPE="part" FSTYPE="ext4" SIZE="476G" PKNAME="/dev/nvme0n1" MOUNTPOINT="/" LABEL="" HOTPLUG="0" RM="0" TRAN=""'
stick() { # FSTYPE MOUNTPOINT [LABEL]: one stick, sda1, next to the computer's own disk
    printf '%s\nPATH="/dev/sda" TYPE="disk" FSTYPE="" SIZE="29G" PKNAME="" MOUNTPOINT="" LABEL="" HOTPLUG="1" RM="1" TRAN="usb"\n' "$nvme" >"$T/lsblk.out"
    printf 'PATH="/dev/sda1" TYPE="part" FSTYPE="%s" SIZE="29G" PKNAME="/dev/sda" MOUNTPOINT="%s" LABEL="%s" HOTPLUG="1" RM="1" TRAN=""\n' "$1" "$2" "${3:-}" >>"$T/lsblk.out"
}
run() { : >"$T/calls"; PATH="$T/fake:$PATH" bash "$HERE/bin/usb" "$@" >"$T/out" 2>&1 </dev/null; }
# answer y|n ARGS...: run with a terminal, answering its question
answer() {
    local a=$1
    shift
    : >"$T/calls"
    printf '%s\n' "$a" | PATH="$T/fake:$PATH" script -qec "bash $HERE/bin/usb $*" /dev/null >"$T/out" 2>&1
}

printf '%s\n' "$nvme" >"$T/lsblk.out"
run
check "only the computer's own disk: no sticks" grep -q "No USB sticks" "$T/out"
run mount
check "...and nothing to mount" bash -c '[ ! -s "$1" ] && grep -q "nothing to mount" "$2"' _ "$T/calls" "$T/out"

stick exfat '' 'Pass\x20words'
run
check "an exFAT stick is listed, its label's space undone from lsblk's escape" grep -q 'sda1 .*exFAT .*Pass words .*not mounted' "$T/out"
run mount
check "usb mount (one stick): mounted as you, yours alone, nothing on it runs" \
    grep -qx 'udisksctl mount -b /dev/sda1 -o nosuid,nodev,noexec,dmask=0077,fmask=0177' "$T/calls"
check "...saying exFAT keeps no owners" grep -q "exFAT keeps no owners" "$T/out"
stick vfat ''
run mount sda1
check "FAT, by its name: the same" grep -qx 'udisksctl mount -b /dev/sda1 -o nosuid,nodev,noexec,dmask=0077,fmask=0177' "$T/calls"
stick ext4 '' BACKUP
run mount BACKUP
check "ext4, by its label: without FAT's options (it keeps its own owners)" grep -qx 'udisksctl mount -b /dev/sda1 -o nosuid,nodev,noexec' "$T/calls"
run mount nvme0n1p2
check "the computer's own disk isn't a stick" bash -c '[ ! -s "$1" ] && grep -q "not a USB stick" "$2"' _ "$T/calls" "$T/out"

# mounted by root (sudo mount): no uid= of yours in its options
stick exfat /media/me/usb
echo "rw,relatime,fmask=0022,dmask=0022,iocharset=utf8" >"$T/findmnt.out"
run
check "a FAT stick mounted by root: the list says you can't write to it" grep -q "BY ROOT" "$T/out"
answer n mount
check "...usb mount asks, and on no leaves it" bash -c '! grep -q umount "$1" && grep -q "left as it is" "$2"' _ "$T/calls" "$T/out"
answer y mount
check "...on yes: unmounted with sudo, then mounted as you" \
    bash -c 'grep -qx "sudo umount /media/me/usb" "$1" && grep -q "udisksctl mount -b /dev/sda1" "$1" && [ "$(grep -n umount "$1" | cut -d: -f1)" -lt "$(grep -n "udisksctl mount" "$1" | cut -d: -f1)" ]' _ "$T/calls"
run mount
check "...and without a terminal to ask on, it is left as it is" bash -c '! grep -q umount "$1"' _ "$T/calls"
echo "rw,uid=$ME,gid=$ME,fmask=0177,dmask=0077" >"$T/findmnt.out"
run
check "mounted as you: just where" grep -q "mounted at /media/me/usb$" "$T/out"
run mount
check "...and mount again does nothing" bash -c '[ ! -s "$1" ] && grep -q "Already mounted" "$2"' _ "$T/calls" "$T/out"
run unmount
check "usb unmount: unmounts, then switches the drive off" \
    bash -c 'grep -qx "udisksctl unmount -b /dev/sda1" "$1" && grep -qx "udisksctl power-off -b /dev/sda" "$1"' _ "$T/calls"

# a stick mounted somewhere sticks aren't (an install on a USB drive, at /)
stick ext4 /
run unmount
check "a drive mounted at / is never unmounted or switched off" test ! -s "$T/calls"
stick exfat /srv/x
: >"$T/findmnt.out"
answer y mount
check "...nor a root mount outside /media, /run/media, /mnt" bash -c '! grep -q umount "$1"' _ "$T/calls"

# encrypted: unlocked, then the file system in it mounted; unmount locks it
stick crypto_LUKS ''
{
    cat "$T/lsblk.out"
    echo 'PATH="/dev/dm-3" TYPE="crypt" FSTYPE="ext4" SIZE="29G" PKNAME="/dev/sda1" MOUNTPOINT="" LABEL="" HOTPLUG="0" RM="0" TRAN=""'
} >"$T/lsblk.unlocked"
run
check "an encrypted stick: listed as locked" grep -q "encrypted .*locked" "$T/out"
run mount
check "...usb mount unlocks it, then mounts what is in it" \
    bash -c 'grep -qx "udisksctl unlock -b /dev/sda1" "$1" && grep -qx "udisksctl mount -b /dev/dm-3 -o nosuid,nodev,noexec" "$1"' _ "$T/calls"
sed 's|PKNAME="/dev/sda1" MOUNTPOINT=""|PKNAME="/dev/sda1" MOUNTPOINT="/media/me/S"|' "$T/lsblk.unlocked" >"$T/lsblk.out"
run unmount
check "...usb unmount: unmounts, locks, switches off, in that order" \
    test "$(grep -oE "^udisksctl [a-z-]+ -b [^ ]+" "$T/calls" | paste -sd,)" = "udisksctl unmount -b /dev/dm-3,udisksctl lock -b /dev/sda1,udisksctl power-off -b /dev/sda"

# two sticks: say which
stick vfat ''
printf '%s\n' 'PATH="/dev/sdb" TYPE="disk" FSTYPE="" SIZE="4G" PKNAME="" MOUNTPOINT="" LABEL="" HOTPLUG="1" RM="1" TRAN="usb"' \
    'PATH="/dev/sdb1" TYPE="part" FSTYPE="vfat" SIZE="4G" PKNAME="/dev/sdb" MOUNTPOINT="" LABEL="CAM" HOTPLUG="1" RM="1" TRAN=""' >>"$T/lsblk.out"
run mount
check "two sticks and no name: asks which, mounts nothing" bash -c '[ ! -s "$1" ] && grep -q "more than one" "$2"' _ "$T/calls" "$T/out"
run mount CAM
check "...by its label: that one" grep -q 'udisksctl mount -b /dev/sdb1' "$T/calls"

# a stranger's label with an escape sequence in it (lsblk shows it as \x1b)
stick vfat '' 'A\x1b]52;c;SGk=\x07'
run
check "a label's control characters are never printed (no escape sequence reaches the terminal)" \
    bash -c '! grep -q $'"'"'\e'"'"' "$1" && grep -q "A?\]52;c;SGk=?" "$1"' _ "$T/out"
# an internal disk that says it is hot-pluggable (many laptops' SATA ports do)
printf '%s\n' "$nvme" 'PATH="/dev/sdb" TYPE="disk" FSTYPE="" SIZE="1T" PKNAME="" MOUNTPOINT="" LABEL="" HOTPLUG="1" RM="0" TRAN="sata"' \
    'PATH="/dev/sdb1" TYPE="part" FSTYPE="ext4" SIZE="1T" PKNAME="/dev/sdb" MOUNTPOINT="/mnt/data" LABEL="DATA" HOTPLUG="1" RM="0" TRAN=""' >"$T/lsblk.out"
run unmount
check "an internal SATA disk that says hot-pluggable isn't a stick: never unmounted or switched off" test ! -s "$T/calls"
run
check "...nor listed" grep -q "No USB sticks" "$T/out"
check "the program has no switch for tests" not grep -q DEBSWAY_USB_TEST "$HERE/bin/usb"

check "the part installs it, with udisks2, in the base" \
    bash -c '. "$1/packages.sh"; printf "%s\n" "${PARTS[@]}" | grep -qx usb && grep -q "apt_install udisks2" "$1/parts/usb.sh" && grep -q "install_bin usb" "$1/parts/usb.sh"' _ "$HERE"

[ "$fails" -eq 0 ]
