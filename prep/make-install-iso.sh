#!/bin/bash
# Builds a Debian 13 install image that installs Debian the way debsway's
# README says (encrypted LVM over the whole disk, no root password, only
# "standard system utilities") and puts debsway in ~/debsway. At the first
# login on the console it asks once "Set it up now?": yes runs
# bash ~/debsway/start.sh, as you, on the running system (not inside the
# installer, where nothing runs yet and nobody can be asked).
#
# It asks you, at install time, for the three things that must be yours:
#   - the disk encryption passphrase (you type it at every boot),
#   - your user's password (also your sudo password),
#   - "Write the changes to disks?", which names the disk it will erase.
# Everything else is answered (data/install-iso-preseed.cfg). Nothing secret
# is put on the image.
#
# The disk: the installer's own medium (the stick) is left out, and if exactly
# one disk is left it is chosen; with more, the installer asks which
# (data/install-iso-disk.sh). The disk is first filled with random data (slow;
# --no-erase skips it, and then old data stays readable in the unused space).
#
# The Debian image it starts from is checked first: the list of checksums must
# carry a good signature from the Debian CD signing key (pinned in pins.sh,
# DEBIAN_CD_FPR), and the image must have the checksum in that list. The
# downloaded image is kept in offline/install-iso and checked again next time.
#
# On the image: the last commit of debsway (as tools/pack-usb.sh copies it, so
# nothing from ignore/) and offline/ (Wi-Fi packages, saved Tor Browser and
# Whonix downloads; not offline/install-iso or offline/tails).
#
#   bash prep/make-install-iso.sh [--user NAME] [--keymap us] [--locale en_US.UTF-8]
#                                 [--no-erase] [--scripts FOLDER] [--out FILE]
#   --user     the user to make (default: yours, $(id -un))
#   --keymap   the keyboard layout (default: us); see the README on passphrases
#   --scripts  a folder of your own, copied to ~/scripts in the new system
# Then it offers to write the image to a USB stick (as tails-usb does: only USB
# sticks, you type its name, and it reads it back to check).
# It runs as you; sudo is asked for only to install xorriso if it is missing
# (it offers to, and removes it again at the end, whether the build worked or
# not; one you had before stays) and to write a stick.
# Test it in a VM first if you can (the end of this script says how).
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
. "$DEBSWAY_DIR/lib/install-iso.sh"
. "$DEBSWAY_DIR/lib/tails.sh"
not_root

user=$(id -un) keymap=us locale=en_US.UTF-8 erase=true scripts='' out='' choice=''
while [ $# -gt 0 ]; do
    case $1 in
        --user) user=${2:-}; shift 2 ;;
        --keymap) keymap=${2:-}; shift 2 ;;
        --locale) locale=${2:-}; shift 2 ;;
        --no-erase) erase=false; shift ;;
        --scripts) scripts=${2:-}; shift 2 ;;
        --out) out=${2:-}; shift 2 ;;
        *) die "Usage: bash prep/make-install-iso.sh [--user NAME] [--keymap us] [--locale en_US.UTF-8] [--no-erase] [--scripts FOLDER] [--out FILE]" ;;
    esac
done
user_ok "$user" || die "\"$user\" can't be a user name (lowercase letters, digits, _ and -, starting with a letter; not root)."
keymap_ok "$keymap" || die "\"$keymap\" doesn't look like a keyboard layout (us, de, fr, gb...)."
locale_ok "$locale" || die "\"$locale\" doesn't look like a locale (en_US.UTF-8, de_DE.UTF-8...)."
[ -z "$scripts" ] || [ -d "$scripts" ] || die "No folder $scripts."
for c in wget gpg sha512sum md5sum git; do
    command -v "$c" >/dev/null || die "$c is missing. Install it with: sudo apt install $([ "$c" = md5sum ] || [ "$c" = sha512sum ] && echo coreutils || echo "$c")"
done
# At the end, whatever happens: the temporary folder goes, and so does
# xorriso if this run installed it (a marker package, so apt takes out just
# what came with it)
work='' installed_here=false
cleanup() {
    [ -z "$work" ] || rm -rf "$work"
    if $installed_here; then
        note "Removing xorriso again (it was only needed to build the image)."
        apt_purge >/dev/null 2>&1 || warn "Couldn't remove it; do it yourself with: sudo apt purge $(apt_marker)"
    fi
}
trap cleanup EXIT

# xorriso builds the image: the only step here that needs sudo, besides writing
# a stick at the end
if ! command -v xorriso >/dev/null; then
    note "xorriso, which builds the image, isn't installed. It is removed again at the end."
    ask "Install it for now (needs your sudo password)?" y ||
        die "Nothing was built. Install it yourself with: sudo apt install xorriso"
    installed_here=true
    apt_install xorriso
fi

SAVED=$DEBSWAY_DIR/offline/install-iso
mkdir -p "$SAVED"
work=$(mktemp -d)

say "The newest Debian 13 installer image"
wget -q -O "$work/SHA512SUMS" "$DEBIAN_CD_BASE/SHA512SUMS" &&
    wget -q -O "$work/SHA512SUMS.sign" "$DEBIAN_CD_BASE/SHA512SUMS.sign" ||
    die "Couldn't download Debian's list of image checksums."
verify_detached "$DEBIAN_CD_FPR" "$DEBIAN_CD_KEY_URL" "$work/SHA512SUMS.sign" "$work/SHA512SUMS" ||
    die "Debian's list of checksums isn't signed by the Debian CD signing key. Nothing was built."
name=$(netinst_name "$work/SHA512SUMS")
[ -n "$name" ] || die "No netinst image in Debian's list."
iso=$SAVED/$name
note "$name (the list is signed by the Debian CD signing key)"
if [ -f "$iso" ] && netinst_ok "$work/SHA512SUMS" "$iso" "$name"; then
    note "Using the saved copy, checked again: $iso"
else
    wget -q --show-progress -c -O "$iso.part" "$DEBIAN_CD_BASE/$name" || die "The download didn't finish; run this again to go on."
    if ! netinst_ok "$work/SHA512SUMS" "$iso.part" "$name"; then
        rm -f "$iso.part"
        die "The image doesn't have the checksum in Debian's signed list, so it was deleted."
    fi
    mv "$iso.part" "$iso"
    for f in "$SAVED"/debian-*-netinst.iso; do [ "$f" = "$iso" ] || rm -f "$f"; done
    note "Checked: $iso"
fi
[ -n "$out" ] || out=$SAVED/${name%.iso}-debsway.iso

say "What goes on it"
stage=$work/stage
mkdir -p "$stage/debsway-install" "$stage/debsway" "$stage/isolinux" "$stage/boot/grub"
fill_preseed "$DEBSWAY_DIR/data/install-iso-preseed.cfg" "$user" "$locale" "$keymap" "$erase" >"$stage/debsway-install/preseed.cfg"
cp "$DEBSWAY_DIR/data/install-iso-disk.sh" "$stage/debsway-install/disk.sh"
cp "$DEBSWAY_DIR/data/install-iso-late.sh" "$stage/debsway-install/late.sh"
cp "$DEBSWAY_DIR/data/install-iso-first-login.sh" "$stage/debsway-install/first-login.sh"
if [ -n "$scripts" ]; then cp -R "$scripts" "$stage/debsway-install/scripts"; note "Your scripts: $scripts -> ~/scripts"; fi
# debsway: the last commit, then offline/ but the installers themselves
git -C "$DEBSWAY_DIR" archive --format=tar HEAD | tar -x -C "$stage/debsway" ||
    die "Couldn't take debsway's last commit (is $DEBSWAY_DIR a git checkout?)."
if [ -d "$DEBSWAY_DIR/offline" ]; then
    mkdir -p "$stage/debsway/offline"
    (cd "$DEBSWAY_DIR/offline" && find . -mindepth 1 -maxdepth 1 ! -name install-iso ! -name tails -exec cp -R {} "$stage/debsway/offline/" \;)
fi
note "debsway $(git -C "$DEBSWAY_DIR" describe --always --dirty 2>/dev/null), user $user, keyboard $keymap, $locale, $([ "$erase" = true ] && echo "the disk filled with random data first" || echo "no random fill")"
[ -z "$(git -C "$DEBSWAY_DIR" status --porcelain 2>/dev/null)" ] ||
    warn "debsway has changes that aren't committed; only the last commit goes on the image."

say "The boot menus"
xorriso -osirrox on -indev "$iso" \
    -extract /boot/grub/grub.cfg "$stage/boot/grub/grub.cfg" \
    -extract /isolinux/menu.cfg "$stage/isolinux/menu.cfg" \
    -extract /isolinux/gtk.cfg "$stage/isolinux/gtk.cfg" \
    -extract /md5sum.txt "$stage/md5sum.txt" >/dev/null 2>&1 || die "Couldn't read the boot menus from $iso."
chmod u+w "$stage/boot/grub/grub.cfg" "$stage/isolinux/menu.cfg" "$stage/isolinux/gtk.cfg" "$stage/md5sum.txt"
grub_add_entry "$stage/boot/grub/grub.cfg" || die "The image's GRUB menu isn't as expected (a new Debian release?); nothing was built."
isolinux_edit "$stage/isolinux/menu.cfg" "$stage/isolinux/gtk.cfg" || die "The image's BIOS menu isn't as expected; nothing was built."
isolinux_entry >"$stage/isolinux/debsway.cfg"
(cd "$stage" && find debsway-install debsway -type f | sed 's|^|./|') >"$work/added"
mapfile -t added <"$work/added"
md5_update "$stage/md5sum.txt" "$stage" ./boot/grub/grub.cfg ./isolinux/menu.cfg ./isolinux/gtk.cfg ./isolinux/debsway.cfg "${added[@]}"
note "\"Automatic install with debsway\" is the first entry, and the default, in both menus."

say "Building $out"
rm -f "$out"
xorriso -indev "$iso" -outdev "$out" \
    -map "$stage/debsway-install" /debsway-install \
    -map "$stage/debsway" /debsway \
    -map "$stage/boot/grub/grub.cfg" /boot/grub/grub.cfg \
    -map "$stage/isolinux/menu.cfg" /isolinux/menu.cfg \
    -map "$stage/isolinux/gtk.cfg" /isolinux/gtk.cfg \
    -map "$stage/isolinux/debsway.cfg" /isolinux/debsway.cfg \
    -map "$stage/md5sum.txt" /md5sum.txt \
    -boot_image any replay -end >"$work/xorriso.log" 2>&1 || { tail -5 "$work/xorriso.log" >&2; die "xorriso couldn't build the image."; }
note "Built: $out ($(du -h "$out" | cut -f1)), SHA-256 $(sha256sum "$out" | cut -c1-16)..."

cat <<EOF

    Try it in a throwaway VM first, if you can (QEMU; nothing on this computer
    is touched; it asks the same three questions):
      qemu-img create -f qcow2 /tmp/test-disk.qcow2 20G
      qemu-system-x86_64 -enable-kvm -m 2048 -cdrom $out \\
          -drive file=/tmp/test-disk.qcow2,if=virtio -boot d

EOF
if ask "Write it to a USB stick now?" n; then
    mapfile -t disks < <(usb_disks)
    [ ${#disks[@]} -gt 0 ] || die "No USB stick found. Write it later: run this again (the image is kept)."
    for i in "${!disks[@]}"; do
        read -r dname bytes model <<<"${disks[i]}"
        printf '    %d) /dev/%s  %s GB  %s\n' $((i + 1)) "$dname" "$((bytes / 1000000000))" "$model"
    done
    tty_read choice "Which stick (1-${#disks[@]})? "
    [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#disks[@]} ] || die "No stick chosen; nothing was written."
    read -r dname bytes model <<<"${disks[choice - 1]}"
    warn "EVERYTHING on /dev/$dname ($model, $((bytes / 1000000000)) GB) will be erased."
    tty_read choice "Type its name, $dname, to go on: "
    [ "$choice" = "$dname" ] || die "That isn't $dname; nothing was written."
    while read -r part mnt; do
        [ -n "$mnt" ] || continue
        sudo umount "$part" || die "Couldn't unmount $part ($mnt)."
    done < <(lsblk -lnpo NAME,MOUNTPOINTS "/dev/$dname" | awk 'NF > 1')
    write_and_check "$out" "/dev/$dname" || die "Writing didn't work. Try again, or another stick."
    note "Written and read back. Boot the laptop from it and choose \"Automatic install with debsway\"."
fi
