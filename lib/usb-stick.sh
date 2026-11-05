# shellcheck shell=bash
# lib/usb-stick.sh: writing a checked image onto a USB stick (extras/tails-usb.sh,
# extras/get-iso.sh). Sourced after lib.sh. Only whole USB disks are offered,
# never one this system runs from; you type the stick's name to go on; what is
# written is read back and compared.

# usb_disks: the USB disks that could take an image, one per line as
# "NAME SIZE-IN-BYTES MODEL": whole disks on USB, not the one this system runs
# from, and none with a partition this system uses (/, /boot, /home, swap)
usb_disks() {
    local below_root name tran type size model
    # every device the root file system sits on, through dm-crypt and LVM
    below_root=$(lsblk -lno NAME -s "$(findmnt -no SOURCE / 2>/dev/null)" 2>/dev/null)
    while read -r name tran type size model; do
        [ "$tran" = usb ] && [ "$type" = disk ] || continue
        ! grep -qxF "$name" <<<"$below_root" || continue
        if lsblk -lno MOUNTPOINTS "/dev/$name" 2>/dev/null | grep -qxE '/|/boot(/efi)?|/home|\[SWAP\]'; then continue; fi
        printf '%s %s %s\n' "$name" "$size" "${model:--}"
    done < <(lsblk -dbn -o NAME,TRAN,TYPE,SIZE,MODEL 2>/dev/null)
}

# write_and_check IMG DEVICE: writes IMG over DEVICE, then reads it back and
# compares, so a failed write or a bad stick is caught. The device's cache is
# flushed first, so what is read back comes from the stick itself, not from
# memory. Uses $SUDO.
write_and_check() {
    local img=$1 dev=$2 size want got
    size=$(stat -c %s "$img")
    want=$(sha256sum "$img" | cut -d' ' -f1)
    $SUDO dd if="$img" of="$dev" bs=16M conv=fsync status=progress || return 1
    sync
    if [ -b "$dev" ]; then $SUDO blockdev --flushbufs "$dev" || return 1; fi
    got=$($SUDO head -c "$size" "$dev" | sha256sum | cut -d' ' -f1)
    [ "$got" = "$want" ] || { warn "What was read back from $dev isn't the image: the stick may be faulty."; return 1; }
}

# stick_write IMG MIN-BYTES WHAT: asks for a stick (MIN-BYTES or more), has you
# type its name, unmounts it, writes IMG and reads it back. WHAT names the image
# in what is said ("Tails 7.2"). Dies, with nothing written, if anything is off.
stick_write() {
    local img=$1 min=$2 what=$3 disks choice i name bytes model dev part mnt
    say "The USB stick"
    mapfile -t disks < <(usb_disks)
    while [ ${#disks[@]} -eq 0 ]; do
        note "No USB stick found. Plug one in ($(((min + 999999999) / 1000000000)) GB or more; everything on it will be erased)."
        tty_read choice "Press Enter when it's in, or q to stop: "
        [ "$choice" != q ] || die "No stick was written."
        mapfile -t disks < <(usb_disks)
    done
    for i in "${!disks[@]}"; do
        read -r name bytes model <<<"${disks[i]}"
        printf '    %d) /dev/%s  %s GB  %s\n' $((i + 1)) "$name" "$((bytes / 1000000000))" "$model"
    done
    tty_read choice "Which stick (1-${#disks[@]})? "
    [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#disks[@]} ] || die "No stick chosen; nothing was written."
    read -r name bytes model <<<"${disks[choice - 1]}"
    dev=/dev/$name
    [ "$bytes" -ge "$min" ] || die "$dev holds $((bytes / 1000000000)) GB; $what needs $(((min + 999999999) / 1000000000)) GB or more. Nothing was written."
    warn "EVERYTHING on $dev ($model, $((bytes / 1000000000)) GB) will be erased."
    tty_read choice "Type its name, $name, to go on: "
    [ "$choice" = "$name" ] || die "That isn't $name; nothing was written."

    # Its partitions may be mounted (USB automount): unmount them first
    while read -r part mnt; do
        [ -n "$mnt" ] || continue
        sudo umount "$part" || die "Couldn't unmount $part ($mnt); close what uses it and try again."
    done < <(lsblk -lnpo NAME,MOUNTPOINTS "$dev" | awk 'NF > 1')

    say "Writing $what to $dev (a few minutes)"
    write_and_check "$img" "$dev" || die "Writing didn't work. Try again, or another stick."
}
