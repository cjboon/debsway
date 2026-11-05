#!/bin/bash
# encrypt-usb.sh: erases a USB stick and makes it one encrypted (LUKS2) partition
# with an ext4 file system that is yours, for backups and keys. It offers only
# USB disks, never the one this system runs from, and you type the stick's name
# before anything is erased. After it, the usb command opens and locks the stick.
# Usage: bash encrypt-usb.sh [NAME]     NAME: the stick, such as sdb
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/usb-stick.sh"
not_root

case ${1:-} in
    -h | --help) sed -n '2,6p' "$0" | sed 's/^# \?//'; exit 0 ;;
    -*) die "Usage: bash encrypt-usb.sh [NAME]" ;;
esac

need_tools cryptsetup:cryptsetup mkfs.ext4:e2fsprogs sfdisk:fdisk wipefs:util-linux

mapfile -t disks < <(usb_disks)
[ ${#disks[@]} -gt 0 ] || die "No USB stick found. Plug one in and run this again."

say "USB sticks"
for i in "${!disks[@]}"; do
    read -r name bytes model <<<"${disks[i]}"
    printf '  %d) %s  %s MB  %s\n' "$((i + 1))" "$name" "$((bytes / 1000000))" "$model"
done

line=
if [ -n "${1:-}" ]; then
    for d in "${disks[@]}"; do
        [ "${d%% *}" != "$1" ] || line=$d
    done
    [ -n "$line" ] || die "$1 isn't one of these. Nothing was changed."
elif [ ${#disks[@]} -eq 1 ]; then
    line=${disks[0]}
else
    tty_read choice "    Which one (its number)? "
    [[ ${choice:-} =~ ^[0-9]{1,3}$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#disks[@]} ] ||
        die "That isn't one of them. Nothing was changed."
    line=${disks[choice - 1]}
fi
read -r name bytes model <<<"$line"
[[ $name =~ ^[a-z][a-z0-9]*$ ]] || die "Unexpected device name: $name"
dev=/dev/$name

if grep -qx crypt <<<"$(lsblk -ln -o TYPE "$dev")"; then
    die "$name is unlocked and in use. Lock it first (usb unmount), then run this again."
fi

warn "EVERYTHING on $name ($((bytes / 1000000)) MB, $model) will be erased, for good."
tty_read typed "    Type its name, $name, to go on: "
[ "${typed:-}" = "$name" ] || die "Nothing was changed."
tty_read label "    A name for the stick (Enter: WREN-USB): "
label=${label:-WREN-USB}
[[ $label =~ ^[A-Za-z0-9_-]{1,16}$ ]] || die "A name is up to 16 letters, digits, - and _. Nothing was changed."

sudo -v || die "sudo didn't accept the password. Nothing was changed."

mapper=wren-usb-$$
mnt=$(mktemp -d)
opened=false
# shellcheck disable=SC2329  # runs from the EXIT trap
cleanup() {
    sudo umount "$mnt" 2>/dev/null || true
    if $opened; then sudo cryptsetup close "$mapper" 2>/dev/null || true; fi
    rmdir "$mnt" 2>/dev/null || true
}
trap cleanup EXIT

say "Erasing $name"
while read -r m; do
    [ -z "$m" ] || sudo umount "$m"
done < <(lsblk -lno MOUNTPOINTS "$dev" 2>/dev/null)
sudo wipefs -a "$dev" >/dev/null
printf 'type=83\n' | sudo sfdisk --quiet "$dev"
sudo udevadm settle 2>/dev/null || true
part=$(lsblk -lnpo NAME,TYPE "$dev" | awk '$2 == "part" { print $1; exit }')
[ -n "$part" ] || die "The new partition on $name didn't show up. Unplug the stick, plug it in and run this again."

say "Encrypting it"
note "Choose a passphrase (diceware -n 6 makes a good one) and keep it somewhere other"
note "than this computer: without it, what is on the stick is gone for good."
sudo cryptsetup luksFormat -q --type luks2 --verify-passphrase "$part" || die "It wasn't encrypted."
note "Now the same passphrase once more, to open it and make its file system."
sudo cryptsetup open "$part" "$mapper" || die "It didn't open with that passphrase."
opened=true

say "Making its file system, yours alone"
sudo mkfs.ext4 -q -L "$label" "/dev/mapper/$mapper"
sudo mount "/dev/mapper/$mapper" "$mnt"
sudo chown "$(id -un):$(id -gn)" "$mnt"
sudo chmod 700 "$mnt"
sudo umount "$mnt"
sudo cryptsetup close "$mapper"
opened=false

say "Done: $name is encrypted and locked"
note "Open it:  usb mount ${part##*/}   (it asks for the passphrase and says where it is)"
note "Lock it:  usb unmount ${part##*/}  (also switches the stick off)"
