#!/bin/bash
# Copies debsway onto a USB stick (or any folder): the committed files, plus
# the saved downloads in offline/. Nothing from ignore/ (personal files) or
# untracked files goes along, and a stick that already has a debsway folder
# gets only the downloads that changed.
#
#   bash tools/pack-usb.sh /media/you/STICK
#
# It copies the last commit, so commit what you want on the stick first.
#
# The stick is also labelled DEBSWAY (it asks first), so that on a fresh
# install one line finds it, whatever the device is called:
#   sudo mount -L DEBSWAY /mnt && bash /mnt/debsway/start.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
not_root

dest=${1:-}
# A device name (/dev/sda) instead of a folder: say where it is mounted, and
# whether it is a USB drive or a disk of this computer
if [[ $dest == /dev/* ]]; then
    [ -b "$dest" ] || die "There is no drive $dest. Plug the stick in, and give the folder where it is mounted."
    warn "$dest is a drive, not a folder. Give the folder where the stick is mounted."
    disk=$(lsblk -dn -o PKNAME "$dest" 2>/dev/null || true)
    [ -n "$disk" ] || disk=${dest#/dev/}
    lsblk -o NAME,SIZE,TRAN,LABEL,MOUNTPOINT "/dev/$disk" | sed 's/^/    /'
    if ! lsblk -dn -o RM,TRAN "/dev/$disk" 2>/dev/null | grep -qE '^ *1 |usb *$'; then
        die "/dev/$disk isn't a USB drive: it is a disk of this computer. Find the stick with: lsblk -o NAME,SIZE,TRAN,LABEL,MOUNTPOINT"
    fi
    mnt=$(lsblk -ln -o MOUNTPOINT "$dest" | grep -m1 '^/' || true)
    [ -n "$mnt" ] || die "The stick isn't mounted: open it in your file manager, then give its folder."
    die "Its folder is $mnt, so: bash tools/pack-usb.sh \"$mnt\""
fi
[ -n "$dest" ] && [ -d "$dest" ] || die "Usage: bash tools/pack-usb.sh /path/to/the/stick"
command -v git >/dev/null || die "git is missing."
git -C "$DEBSWAY_DIR" rev-parse --git-dir >/dev/null 2>&1 || die "$DEBSWAY_DIR isn't a git checkout."
if [ -n "$(git -C "$DEBSWAY_DIR" status --porcelain --untracked-files=no)" ]; then
    warn "You have changes that aren't committed; the stick gets the last commit without them."
fi

target="$dest/debsway"
LABEL=DEBSWAY

# label_stick: puts the label DEBSWAY on the stick, if it has another one.
# Only a removable (USB) drive is ever relabelled, never a disk of this computer.
label_stick() {
    local src fstype disk label tool need pkg mnt unmounted
    src=$(findmnt -n -o SOURCE -T "$dest" 2>/dev/null || true)
    fstype=$(findmnt -n -o FSTYPE -T "$dest" 2>/dev/null || true)
    if [ ! -b "$src" ]; then
        warn "Can't tell which drive $dest is on, so its label isn't checked."
        warn "start.sh finds the stick by the label $LABEL: set it yourself (fatlabel or e2label)."
        return 0
    fi
    label=$(lsblk -dn -o LABEL "$src" 2>/dev/null || true)
    [ "$label" != "$LABEL" ] || return 0
    disk=$(lsblk -dn -o PKNAME "$src" 2>/dev/null || true)
    [ -n "$disk" ] || disk=${src#/dev/}
    if ! lsblk -dn -o RM,TRAN "/dev/$disk" 2>/dev/null | grep -qE '^ *1 |usb *$'; then
        warn "$src doesn't look like a removable drive, so its label is left alone ('${label:-none}')."
        return 0
    fi
    say "Labelling the stick $LABEL"
    note "It is labelled '${label:-none}' now. On the new system one line finds it by the"
    note "label: sudo mount -L $LABEL /mnt && bash /mnt/debsway/start.sh"
    ask "Label $src ($fstype) $LABEL?" y || { warn "Not labelled: that line won't find it until you do."; return 0; }
    case $fstype in
        vfat) tool=(fatlabel "$src" "$LABEL"); need=fatlabel; pkg=dosfstools ;;
        ext2 | ext3 | ext4) tool=(e2label "$src" "$LABEL"); need=e2label; pkg=e2fsprogs ;;
        exfat) tool=(exfatlabel "$src" "$LABEL"); need=exfatlabel; pkg=exfatprogs ;;
        ntfs | ntfs3) tool=(ntfslabel "$src" "$LABEL"); need=ntfslabel; pkg=ntfs-3g ;;
        *) warn "Don't know how to label a $fstype drive. Label it $LABEL yourself."; return 0 ;;
    esac
    command -v "$need" >/dev/null || { warn "$need isn't installed (sudo apt install $pkg)."; return 0; }
    # Labelled while unmounted: a mounted FAT drive gets a "boot sector differs
    # from its backup" complaint, and exFAT and NTFS can't be labelled mounted at all
    mnt=$(findmnt -n -o TARGET -T "$dest")
    sync
    if sudo umount "$mnt"; then
        unmounted=true
    else
        unmounted=false
        case $fstype in
            exfat | ntfs | ntfs3)
                warn "Couldn't unmount $mnt, and $fstype can only be labelled unmounted. Close what uses it, then:"
                warn "  sudo umount $mnt && sudo ${tool[*]}"
                return 0 ;;
        esac
    fi
    if sudo "${tool[@]}"; then
        if $unmounted; then
            note "Labelled $LABEL and unmounted the stick: you can unplug it."
        else
            note "Labelled $LABEL. Unmount the stick before you unplug it."
        fi
    else
        warn "Labelling failed; start.sh finds the stick by the label $LABEL, so set it yourself: sudo ${tool[*]}"
    fi
}

say "Copying the committed files to $target"
mkdir -p "$target"
# The old copy goes, except the big downloads
find "$target" -mindepth 1 -maxdepth 1 ! -name offline -exec rm -rf {} +
git -C "$DEBSWAY_DIR" archive --format=tar HEAD | tar -x --no-same-permissions -C "$target"
# A stick's filesystem may not keep permissions, which is why the README
# says to run scripts with bash.

if [ -d "$DEBSWAY_DIR/offline" ]; then
    say "Copying the saved downloads (offline/)"
    mkdir -p "$target/offline"
    cp -ru --no-preserve=mode,ownership "$DEBSWAY_DIR/offline"/. "$target/offline"/
    # Downloads that were replaced or deleted here
    (cd "$target/offline" && find . -type f | while read -r f; do
        [ -e "$DEBSWAY_DIR/offline/$f" ] || rm -f "$f"
    done)
fi
sync

# A page to read on another computer (or print): the stick can't show it on
# the new machine until it is mounted
cat >"$dest/START-HERE.txt" <<EOF
debsway: how to start on a fresh Debian install

1. Plug in this stick. At the text console, log in and type:

     sudo mount -L $LABEL /mnt && bash /mnt/debsway/start.sh

   It copies debsway to your home folder, unmounts the stick, gets you
   online with wifi.sh if you aren't, and starts install-base.sh, which
   explains what it will do and asks before it changes anything.

2. If you set a root password in the installer, sudo isn't installed. Use:

     su -c "mount -L $LABEL /mnt"
     bash /mnt/debsway/start.sh

   and follow what it says (it uses prep/setup-sudo.sh).

3. If "mount" can't find the label: lsblk -f   shows the drives and their
   labels, and   dmesg | tail   shows the name the stick got when you plugged
   it in (e.g. sdb1). Then:  sudo mount /dev/sdb1 /mnt

Read the scripts before you run them: they change system files.
EOF
label_stick
note "Done: $target"
note "On the new system: sudo mount -L $LABEL /mnt && bash /mnt/debsway/start.sh"
