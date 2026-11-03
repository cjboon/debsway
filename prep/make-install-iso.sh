#!/bin/bash
# Builds a Debian 13 install image that installs Debian the way Wren Linux's
# README says (encrypted LVM over the whole disk, no root password, no
# desktop) and puts Wren Linux in ~/wren. At the first
# login on the console it asks once "Set it up now?": yes runs
# bash ~/wren/start.sh, as you, on the running system (not inside the
# installer, where nothing runs yet and nobody can be asked).
#
# It asks you, at install time, for the three things that must be yours:
#   - the disk encryption passphrase (you type it at every boot; not with --noencrypt),
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
# It is Debian's text-only live "standard" image: the installer copies the live
# system onto the disk rather than choosing packages, so what you get is what
# that image contains (parts/no-live-extras.sh later takes out what Wren Linux
# doesn't use: avahi, printing, hw-probe...).
#
# On the image: the last commit of Wren Linux (as tools/pack-usb.sh copies it, so
# nothing from ignore/) and offline/ (Wi-Fi packages, saved Tor Browser and
# Whonix downloads; not offline/install-iso or offline/tails). The Wi-Fi
# packages are refreshed first when wifi.sh would soon refuse them as too old
# (prep/fetch-offline-debs.sh), and it says until when they work.
#
#   bash prep/make-install-iso.sh [--user NAME] [--keymap us] [--locale en_US.UTF-8]
#                                 [--timezone Area/City] [--no-erase] [--noencrypt]
#                                 [--autologin] [--simplesway] [--scripts FOLDER] [--out FILE]
#   --user     the user to make (default: yours, $(id -un))
#   --keymap   the keyboard layout (default: us); see the README on passphrases
#   --timezone the clock's time zone, like Europe/Berlin (default: this
#              computer's; the clock shows local time, kept right over NTP)
#   --noencrypt  the disk is NOT encrypted: no passphrase at boot, but anyone
#              holding the laptop (or its disk) can read everything on it
#   --autologin  tty1 logs you in without your password, so it starts straight
#              into sway (extras/autologin.sh does the same on an installed system)
#   --simplesway  one workspace: the first login's install list starts with
#              one-workspace ticked (no workspace keys or buttons; untick it there)
#   --scripts  a folder of your own, copied to ~/scripts in the new system
# Then it offers to write the image to a USB stick (as tails-usb does: only USB
# sticks, you type its name, and it reads it back to check).
# It runs as you; sudo is asked for only to install what it needs and is
# missing (xorriso, wget, gpg, git) and to write a stick. xorriso is needed
# only to build the image, so one this run installed is removed again at the
# end, whether the build worked or not (one you had before stays).
# Test it in a VM first if you can (the end of this script says how).
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/install-iso.sh"
. "$WREN_DIR/lib/offline.sh"
. "$WREN_DIR/lib/tails.sh"
not_root

user=$(id -un) keymap=us locale=en_US.UTF-8 timezone=$(this_timezone) erase=true encrypt=true autologin=false simplesway=false scripts='' out='' choice=''
while [ $# -gt 0 ]; do
    case $1 in
        --user) user=${2:-}; shift 2 ;;
        --keymap) keymap=${2:-}; shift 2 ;;
        --locale) locale=${2:-}; shift 2 ;;
        --timezone) timezone=${2:-}; shift 2 ;;
        --no-erase) erase=false; shift ;;
        --noencrypt) encrypt=false; shift ;;
        --autologin) autologin=true; shift ;;
        --simplesway) simplesway=true; shift ;;
        # (the live image is the only one now; kept so old commands still work)
        --live) shift ;;
        --scripts) scripts=${2:-}; shift 2 ;;
        --out) out=${2:-}; shift 2 ;;
        *) die "Usage: bash prep/make-install-iso.sh [--user NAME] [--keymap us] [--locale en_US.UTF-8] [--timezone Area/City] [--no-erase] [--noencrypt] [--autologin] [--simplesway] [--scripts FOLDER] [--out FILE]" ;;
    esac
done
user_ok "$user" || die "\"$user\" can't be a user name (lowercase letters, digits, _ and -, starting with a letter; not root)."
keymap_ok "$keymap" || die "\"$keymap\" doesn't look like a keyboard layout (us, de, fr, gb...)."
locale_ok "$locale" || die "\"$locale\" doesn't look like a locale (en_US.UTF-8, de_DE.UTF-8...)."
timezone_ok "$timezone" || die "\"$timezone\" isn't a time zone (like Europe/Berlin or America/New_York; see: timedatectl list-timezones)."
[ -z "$scripts" ] || [ -d "$scripts" ] || die "No folder $scripts."
if ! $encrypt; then
    warn "--noencrypt: the new system's disk won't be encrypted. Anyone who has the laptop,"
    warn "or takes its disk out, can read every file on it, and change them."
    $autologin && warn "With --autologin too, turning it on is enough to be logged in as you."
    ask "Build an image that installs without disk encryption?" n || die "Nothing was built."
fi
# What it needs, installed now if missing
need_tools wget:wget gpg:gpg sha512sum:coreutils md5sum:coreutils git:git
# At the end, whatever happens: the temporary folder goes, and so does
# xorriso if this run installed it. It has a marker package of its own, so
# that taking it out leaves the tools above alone.
XORRISO_OWNER=make-install-iso-xorriso
work='' installed_here=false
cleanup() {
    [ -z "$work" ] || rm -rf "$work"
    if $installed_here; then
        note "Removing xorriso again (it was only needed to build the image)."
        WREN_OWNER=$XORRISO_OWNER apt_purge >/dev/null 2>&1 ||
            warn "Couldn't remove it; do it yourself with: sudo apt purge wren-$XORRISO_OWNER"
    fi
}
trap cleanup EXIT

# xorriso builds the image
if ! command -v xorriso >/dev/null; then
    note "Installing xorriso, which builds the image, for this run only."
    installed_here=true
    WREN_OWNER=$XORRISO_OWNER apt_install xorriso
fi

SAVED=$OFFLINE_DIR/install-iso
mkdir -p "$SAVED"
work=$(mktemp -d)

say "The newest Debian 13 live (standard) installer image"
base=$DEBIAN_LIVE_BASE
wget -q -O "$work/SHA512SUMS" "$base/SHA512SUMS" &&
    wget -q -O "$work/SHA512SUMS.sign" "$base/SHA512SUMS.sign" ||
    die "Couldn't download Debian's list of image checksums."

verify_detached "$DEBIAN_CD_FPR" "$DEBIAN_CD_KEY_URL" \
    "$work/SHA512SUMS.sign" "$work/SHA512SUMS" ||
    die "Debian's list of checksums isn't signed by the Debian CD signing key. Nothing was built."

name=$(live_name "$work/SHA512SUMS")
[ -n "$name" ] || die "No live standard image in Debian's list."
iso=$SAVED/$name

note "$name (the list is signed by the Debian CD signing key)"

if [ -f "$iso" ] && debian_cd_image_ok "$work/SHA512SUMS" "$iso" "$name"; then
    note "Using the saved copy, checked again: $iso"
else
    wget -q --show-progress -c -O "$iso.part" "$base/$name" ||
        die "The download didn't finish; run this again to go on."
    if ! debian_cd_image_ok "$work/SHA512SUMS" "$iso.part" "$name"; then
        rm -f "$iso.part"
        die "The image doesn't have the checksum in Debian's signed list, so it was deleted."
    fi
    mv "$iso.part" "$iso"
    # Older downloads go, and DVD-1 ones from before the live image was the
    # only one (about 4 GB each). Images you built from them stay.
    for f in "$SAVED"/debian-live-*-standard.iso "$SAVED"/debian-*-DVD-1.iso; do
        [ "$f" = "$iso" ] || rm -f "$f"
    done
    note "Checked: $iso"
fi
[ -n "$out" ] || out=$SAVED/${name%.iso}-wren.iso

say "The offline Wi-Fi packages"
offline_debs_refresh

say "What goes on it"
stage=$work/stage
mkdir -p "$stage/wren-install" "$stage/wren" "$stage/isolinux" "$stage/boot/grub"
fill_preseed "$WREN_DIR/data/install-iso-preseed.cfg" "$user" "$locale" "$keymap" "$erase" "$timezone" \
    "$($encrypt && echo crypto || echo regular)" >"$stage/wren-install/preseed.cfg"
# late.sh installs it if it is there
if $autologin; then autologin_conf "$user" >"$stage/wren-install/autologin.conf"; fi
# the first install list starts with these ticked (late.sh puts it in ~/.config/wren)
if $simplesway; then echo one-workspace >"$stage/wren-install/preselect"; fi
cp "$WREN_DIR/data/install-iso-disk.sh" "$stage/wren-install/disk.sh"
cp "$WREN_DIR/data/install-iso-net.sh" "$stage/wren-install/net.sh"
cp "$WREN_DIR/data/install-iso-late.sh" "$stage/wren-install/late.sh"
cp "$WREN_DIR/data/install-iso-first-login.sh" "$stage/wren-install/first-login.sh"
if [ -n "$scripts" ]; then cp -R "$scripts" "$stage/wren-install/scripts"; note "Your scripts: $scripts -> ~/scripts"; fi
# Wren Linux: the last commit, then offline/ but the installers themselves
git -C "$WREN_DIR" archive --format=tar HEAD | tar -x -C "$stage/wren" ||
    die "Couldn't take Wren Linux's last commit (is $WREN_DIR a git checkout?)."
if [ -d "$OFFLINE_DIR" ]; then
    mkdir -p "$stage/wren/offline"
    (cd "$OFFLINE_DIR" && find . -mindepth 1 -maxdepth 1 ! -name install-iso ! -name tails -exec cp -R {} "$stage/wren/offline/" \;)
fi
note "Wren Linux $(git -C "$WREN_DIR" describe --always --dirty 2>/dev/null), user $user, keyboard $keymap, $locale, time zone $timezone, $($encrypt || echo "NOT encrypted, ")$($encrypt && [ "$erase" = true ] && echo "the disk filled with random data first" || echo "no random fill")$($autologin && echo ", logged in on tty1 without a password")$($simplesway && echo ", one workspace")"
[ -z "$(git -C "$WREN_DIR" status --porcelain 2>/dev/null)" ] ||
    warn "Wren Linux has changes that aren't committed; only the last commit goes on the image."

say "The boot menus"
# the BIOS menu's second file, with the live system's entries
second=live.cfg
xorriso -osirrox on -indev "$iso" \
    -extract /boot/grub/grub.cfg "$stage/boot/grub/grub.cfg" \
    -extract /isolinux/menu.cfg "$stage/isolinux/menu.cfg" \
    -extract "/isolinux/$second" "$stage/isolinux/$second" \
    -extract /md5sum.txt "$stage/md5sum.txt" >/dev/null 2>&1 || die "Couldn't read the boot menus from $iso."
chmod u+w "$stage/boot/grub/grub.cfg" "$stage/isolinux/menu.cfg" "$stage/isolinux/$second" "$stage/md5sum.txt"
grub_add_entry "$stage/boot/grub/grub.cfg" || die "The image's GRUB menu isn't as expected (a new Debian release?); nothing was built."
isolinux_edit "$stage/isolinux/menu.cfg" "$stage/isolinux/$second" || die "The image's BIOS menu isn't as expected; nothing was built."
isolinux_entry >"$stage/isolinux/wren.cfg"
(cd "$stage" && find wren-install Wren Linux -type f | sed 's|^|./|') >"$work/added"
mapfile -t added <"$work/added"
md5_update "$stage/md5sum.txt" "$stage" ./boot/grub/grub.cfg ./isolinux/menu.cfg "./isolinux/$second" ./isolinux/wren.cfg "${added[@]}"
note "\"Automatic install with Wren Linux\" is the first entry, and the default, in both menus."

say "Building $out"
rm -f "$out"
xorriso -indev "$iso" -outdev "$out" \
    -map "$stage/wren-install" /wren-install \
    -map "$stage/wren" /wren \
    -map "$stage/boot/grub/grub.cfg" /boot/grub/grub.cfg \
    -map "$stage/isolinux/menu.cfg" /isolinux/menu.cfg \
    -map "$stage/isolinux/$second" "/isolinux/$second" \
    -map "$stage/isolinux/wren.cfg" /isolinux/wren.cfg \
    -map "$stage/md5sum.txt" /md5sum.txt \
    -boot_image any replay -end >"$work/xorriso.log" 2>&1 || { tail -5 "$work/xorriso.log" >&2; die "xorriso couldn't build the image."; }
note "Built: $out ($(du -h "$out" | cut -f1)), SHA-256 $(sha256sum "$out" | cut -c1-16)..."

cat <<EOF

    Try it in a throwaway VM first, if you can (QEMU; nothing on this computer
    is touched; it asks the same three questions):
      qemu-img create -f qcow2 ~/test-disk.qcow2 20G
      qemu-system-x86_64 -enable-kvm -m 2048 -cdrom $out \\
          -drive file=$HOME/test-disk.qcow2,if=virtio -boot d

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
    note "Written and read back. Boot the laptop from it and choose \"Automatic install with Wren Linux\"."
fi
