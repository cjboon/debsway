#!/bin/bash
# Start here on a fresh Debian install. From the USB stick (labelled
# DEBSWAY; tools/pack-usb.sh does that), one line:
#
#   sudo mount -L DEBSWAY /mnt && bash /mnt/debsway/start.sh
#
# It copies debsway to ~/debsway, unmounts the stick, gets you online with
# wifi.sh if you aren't, then runs install-base.sh, which explains what it
# will do and asks before changing anything.
# From the copy in your home folder it skips the copying:
#   bash ~/debsway/start.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
not_root

dest="$HOME/debsway"

# Run from the copy, to unmount the stick the first run came from: a drive
# can't be unmounted while a script is still running from it
if [ "${1:-}" = --unmount ]; then
    mnt=$2
    cd "$HOME"
    if command -v sudo >/dev/null; then
        umount_cmd=(sudo umount "$mnt")
    else
        umount_cmd=(su -c "umount $mnt")
    fi
    if "${umount_cmd[@]}"; then
        note "The stick is unmounted: you can unplug it."
    else
        warn "Couldn't unmount $mnt. Leave your shell's current folder if it is inside it (cd ~),"
        warn "then run: ${umount_cmd[*]}   before you unplug the stick."
    fi
elif [ "$DEBSWAY_DIR" != "$dest" ]; then
    say "Copying debsway to $dest"
    if [ -e "$dest" ]; then
        ask "$dest already exists. Replace it? (the old one is kept as ~/debsway.old)" n ||
            die "Nothing was changed. To use the copy you have: bash $dest/start.sh"
        rm -rf "$dest.old"
        mv "$dest" "$dest.old"
    fi
    # Not -a: ownership and modes from the stick (often FAT) mean nothing here
    cp -r "$DEBSWAY_DIR" "$dest" || die "Copying failed (is there room in your home folder?)."
    note "Copied."
    mnt=$(findmnt -n -o TARGET -T "$DEBSWAY_DIR" 2>/dev/null || true)
    # Only a mount that is not the root file system, i.e. the stick itself
    if [ -n "$mnt" ] && [ "$mnt" != / ]; then
        exec bash "$dest/start.sh" --unmount "$mnt"
    fi
    exec bash "$dest/start.sh"
fi

command -v sudo >/dev/null || die "sudo isn't installed (you set a root password in the installer?). Run: su -c \"bash $dest/prep/setup-sudo.sh $USER\"   then log out, log in and run: bash $dest/start.sh"

cd "$dest"
if have_internet; then
    note "You're online."
else
    say "Getting online"
    bash "$dest/wifi.sh" || die "Not online. Fix that (bash $dest/wifi.sh, or plug in a cable) and run: bash $dest/start.sh"
    have_internet || die "Still not online. Run: bash $dest/start.sh   once you are."
fi

say "Installing"
exec bash "$dest/install-base.sh"
