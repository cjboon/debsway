#!/bin/bash
# Checks prep/make-install-iso.sh's pieces without a network, an ISO, xorriso or
# the Debian installer: picking the image from Debian's list, the installer's
# answers (nothing secret, the three questions left to you), the boot menu
# edits (on excerpts of Debian 13's own menu files), md5sum.txt, and the two
# scripts that run inside the installer (choosing the disk, copying debsway),
# with pretend commands. Changes nothing outside a temp folder. Run by test.sh,
# or:  bash tools/test-install-iso.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
. "$HERE/lib/appimage.sh"
. "$HERE/lib/install-iso.sh"
set +e +o pipefail

T=$(mktemp -d)
trap 'chmod -R u+w "$T" 2>/dev/null; rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# ---- the image ----
h() { printf '%0128d' "$1"; }
printf '%s  %s\n' "$(h 1)" debian-13.7.0-amd64-netinst.iso "$(h 2)" debian-edu-13.7.0-amd64-netinst.iso \
    "$(h 3)" debian-mac-13.7.0-amd64-netinst.iso >"$T/SHA512SUMS"
check "the plain netinst image is picked from Debian's list" test "$(netinst_name "$T/SHA512SUMS")" = debian-13.7.0-amd64-netinst.iso
printf '%s  %s\n' "$(h 1)" '../../etc/passwd' >"$T/BAD"
check "a list entry that isn't a netinst image name is ignored" test -z "$(netinst_name "$T/BAD")"
echo "debsway test image" >"$T/debian-13.7.0-amd64-netinst.iso"
sum=$(sha512sum "$T/debian-13.7.0-amd64-netinst.iso" | cut -d' ' -f1)
printf '%s  %s\n' "$sum" debian-13.7.0-amd64-netinst.iso >"$T/SUMS"
check "an image with the listed checksum passes" netinst_ok "$T/SUMS" "$T/debian-13.7.0-amd64-netinst.iso" debian-13.7.0-amd64-netinst.iso
# the download is checked while it is still NAME.part (a check by file name refused every download)
cp "$T/debian-13.7.0-amd64-netinst.iso" "$T/debian-13.7.0-amd64-netinst.iso.part"
check "...also while the download is still called NAME.part" netinst_ok "$T/SUMS" "$T/debian-13.7.0-amd64-netinst.iso.part" debian-13.7.0-amd64-netinst.iso
check "the script checks the download under the image's name" grep -q 'netinst_ok "$work/SHA512SUMS" "$iso.part" "$name"' "$HERE/prep/make-install-iso.sh"
echo changed >>"$T/debian-13.7.0-amd64-netinst.iso"
check "a changed image is refused" not netinst_ok "$T/SUMS" "$T/debian-13.7.0-amd64-netinst.iso" debian-13.7.0-amd64-netinst.iso
check "an image the list doesn't name is refused" not netinst_ok "$T/SUMS" "$T/debian-13.7.0-amd64-netinst.iso.part" debian-14.0.0-amd64-netinst.iso
check "the Debian CD signing key is pinned" test "$DEBIAN_CD_FPR" = DF9B9C49EAA9298432589D76DA87E80D6294BE9B
check "a missing xorriso is offered, installed the debsway way (a marker package)" \
    bash -c 'grep -q "ask \"Install it for now (needs your sudo password)?\" y" "$1" && grep -q "^    apt_install xorriso$" "$1"' _ "$HERE/prep/make-install-iso.sh"
# the clean-up, run on its own: it takes xorriso out only if this run put it in
eval "$(sed -n '/^cleanup() {/,/^}/p' "$HERE/prep/make-install-iso.sh")"
apt_purge() { echo purged >>"$T/purged"; }
work=$T/work; mkdir -p "$work"; installed_here=true
cleanup >/dev/null 2>&1
check "at the end, xorriso is removed again if this run installed it" grep -qx purged "$T/purged"
check "...and the temporary folder is gone" test ! -e "$T/work"
: >"$T/purged"; work=''; installed_here=false
cleanup >/dev/null 2>&1
check "an xorriso that was there before stays" test ! -s "$T/purged"
check "the clean-up runs whatever happens (on exit)" grep -qx 'trap cleanup EXIT' "$HERE/prep/make-install-iso.sh"
check "...and the marker is named for the script, so it comes out cleanly" \
    test "$(cd "$HERE" && env -u DEBSWAY_OWNER bash -c '. ./lib.sh; apt_marker' "$HERE/prep/make-install-iso.sh")" = debsway-make-install-iso

# ---- the installer's answers ----
P=$(fill_preseed "$HERE/data/install-iso-preseed.cfg" me de_DE.UTF-8 de true)
ans=$(grep -v '^[[:space:]]*#' <<<"$P")
check "every @value@ is filled in" not grep -q '@' <<<"$ans"
check "the user, locale and keyboard are the ones asked for" \
    bash -c 'grep -qx "d-i passwd/username string me" <<<"$1" && grep -qx "d-i debian-installer/locale string de_DE.UTF-8" <<<"$1" && grep -qx "d-i keyboard-configuration/xkb-keymap select de" <<<"$1"' _ "$ans"
check "no disk passphrase is set: the installer asks you" not grep -q 'partman-crypto/passphrase' <<<"$ans"
check "no user password is set: the installer asks you" not grep -q 'passwd/user-password' <<<"$ans"
check "\"write the changes to disks?\" isn't answered: the installer asks you" not grep -qE 'partman/confirm |partman-crypto/confirm ' <<<"$ans"
check "no root password: root is locked, your user gets sudo" grep -qx 'd-i passwd/root-login boolean false' <<<"$ans"
check "the whole disk, encrypted LVM" bash -c 'grep -qx "d-i partman-auto/method string crypto" <<<"$1"' _ "$ans"
check "the disk is filled with random data first" grep -qx 'd-i partman-crypto/erase_disks boolean true' <<<"$ans"
check "...unless --no-erase" grep -qx 'd-i partman-crypto/erase_disks boolean false' <(fill_preseed "$HERE/data/install-iso-preseed.cfg" me en_US.UTF-8 us false)
check "only standard system utilities, no desktop" grep -qx 'tasksel tasksel/first multiselect standard' <<<"$ans"
check "no popularity contest" grep -qx 'popularity-contest popularity-contest/participate boolean false' <<<"$ans"
check "packages come over https" grep -qx 'd-i mirror/protocol string https' <<<"$ans"
for bad in root Me '1x' 'a b' 'me;reboot' ''; do check "the user name '$bad' is refused" not user_ok "$bad"; done
for bad in 'us|x' 'u s' 'us;id' ''; do check "the keyboard '$bad' is refused" not keymap_ok "$bad"; done
check "a layout with a variant is fine" keymap_ok 'us(intl)'
for bad in 'en_US' 'en_US.UTF-8;x' ''; do check "the locale '$bad' is refused" not locale_ok "$bad"; done

# ---- the boot menus (excerpts of Debian 13.7.0's own) ----
cat >"$T/grub.cfg" <<'EOF'
set theme=/boot/grub/theme/1
menuentry --hotkey=g 'Graphical install' {
    set background_color=black
    linux    /install.amd/vmlinuz vga=788 --- quiet
    initrd   /install.amd/gtk/initrd.gz
}
menuentry --hotkey=i 'Install' {
    set background_color=black
    linux    /install.amd/vmlinuz vga=788 --- quiet
    initrd   /install.amd/initrd.gz
}
submenu --hotkey=a 'Advanced options ...' {
    menuentry '... Graphical rescue mode' {
        linux    /install.amd/vmlinuz vga=788 rescue/enable=true --- quiet
        initrd   /install.amd/gtk/initrd.gz
    }
}
EOF
cp "$T/grub.cfg" "$T/grub.orig"
grub_add_entry "$T/grub.cfg"
check "GRUB: the automatic install is the first entry (the default)" \
    test "$(grep -m1 '^menuentry' "$T/grub.cfg")" = "menuentry --hotkey=a 'Automatic install with debsway (asks for your passphrase and password)' {"
check "...starting the installer with debsway's answers" grep -qF "vga=788 $AUTO_ARGS --- quiet" "$T/grub.cfg"
check "...and only that entry gets them (rescue mode stays as it was)" test "$(grep -c 'preseed/file=' "$T/grub.cfg")" = 1
check "...nothing else in the menu changes" bash -c 'diff <(sed "1,1d" "$1") <(sed "1d" "$2" | sed "1,5d")' _ "$T/grub.orig" "$T/grub.cfg"
echo 'menuentry "Something else" {' >"$T/odd.cfg"
check "GRUB: a menu that isn't Debian's as expected is refused" not grub_add_entry "$T/odd.cfg"
printf '%s\n' 'include stdmenu.cfg' 'include gtk.cfg' 'include txt.cfg' >"$T/menu.cfg"
printf '%s\n' 'default installgui' 'label installgui' '	menu label ^Graphical install' '	menu default' \
    '	kernel /install.amd/vmlinuz' '	append vga=788 initrd=/install.amd/gtk/initrd.gz --- quiet ' >"$T/gtk.cfg"
isolinux_edit "$T/menu.cfg" "$T/gtk.cfg"
check "BIOS: the menu includes the automatic install before the graphical one" \
    test "$(sed -n 2p "$T/menu.cfg")" = 'include debsway.cfg'
check "...which is the default" grep -qx '	menu default' <(isolinux_entry)
check "...and the graphical install no longer is (its entry stays)" \
    bash -c '! grep -q "menu default\|default installgui" "$1" && grep -q "label installgui" "$1"' _ "$T/gtk.cfg"
check "BIOS: a menu that isn't as expected is refused" not isolinux_edit "$T/menu.cfg" "$T/gtk.cfg"
mkdir -p "$T/root/boot/grub"
echo new >"$T/root/boot/grub/grub.cfg"
printf '%s\n' "0123456789abcdef0123456789abcdef  ./boot/grub/grub.cfg" "fedcba9876543210fedcba9876543210  ./README.txt" >"$T/md5sum.txt"
md5_update "$T/md5sum.txt" "$T/root" ./boot/grub/grub.cfg
check "md5sum.txt: a changed file gets its new checksum" grep -qx "$(md5sum "$T/root/boot/grub/grub.cfg" | cut -d' ' -f1)  ./boot/grub/grub.cfg" "$T/md5sum.txt"
check "...once, and the other lines stay" bash -c '[ "$(grep -c grub.cfg "$1")" = 1 ] && grep -q README "$1"' _ "$T/md5sum.txt"

# ---- inside the installer: which disk ----
D=$HERE/data/install-iso-disk.sh
disk() { # MOUNTED-ON-/cdrom DISK...: what disk.sh sets
    printf '%s /cdrom iso9660 ro 0 0\n' "$1" >"$T/mounts"
    shift
    printf '#!/bin/sh\nprintf "%%s\\n" %s\n' "$*" >"$T/list"
    printf '#!/bin/sh\necho "$@" >>"%s/set"\n' "$T" >"$T/setq"
    chmod +x "$T/list" "$T/setq"
    : >"$T/set"
    DEBSWAY_MOUNTS=$T/mounts DEBSWAY_LIST=$T/list DEBSWAY_SET=$T/setq sh "$D"
    cat "$T/set"
}
out=$(disk /dev/sdb1 /dev/nvme0n1 /dev/sdb)
check "the installer's own stick is left out, the one other disk chosen" grep -qx 'partman-auto/disk /dev/nvme0n1' <<<"$out"
check "...and the boot loader goes on that disk, not the stick" grep -qx 'grub-installer/bootdev /dev/nvme0n1' <<<"$out"
check "a stick on an NVMe-style name is left out too" grep -qx 'partman-auto/disk /dev/sda' <<<"$(disk /dev/nvme1n1p1 /dev/sda /dev/nvme1n1)"
check "...and an SD card (mmcblk0p1)" grep -qx 'partman-auto/disk /dev/sda' <<<"$(disk /dev/mmcblk0p1 /dev/sda /dev/mmcblk0)"
check "from a DVD every disk counts" grep -qx 'partman-auto/disk /dev/sda' <<<"$(disk /dev/sr0 /dev/sda)"
check "two disks besides the stick: nothing is chosen, the installer asks" test -z "$(disk /dev/sdc1 /dev/sda /dev/nvme0n1 /dev/sdc)"
check "no disk besides the stick: nothing is chosen" test -z "$(disk /dev/sdb1 /dev/sdb)"

# ---- inside the installer: debsway into ~/debsway ----
L=$T/late.sh
sed -e "s|/cdrom|$T/cdrom|g" -e "s|/target|$T/target|g" "$HERE/data/install-iso-late.sh" >"$L"
mkdir -p "$T/cdrom/debsway/bin" "$T/cdrom/debsway/extras" "$T/cdrom/debsway-install/scripts" "$T/target/home/me" "$T/fake"
echo x >"$T/cdrom/debsway/README.md"; echo x >"$T/cdrom/debsway/start.sh"; echo x >"$T/cdrom/debsway/bin/keys"
echo x >"$T/cdrom/debsway-install/scripts/mine.txt"
chmod -R a-w "$T/cdrom"
printf '#!/bin/sh\necho "in-target $*" >>"%s/intarget"\n' "$T" >"$T/fake/in-target"
chmod +x "$T/fake/in-target"
PATH="$T/fake:$PATH" sh "$L" me
check "debsway is copied to ~/debsway" test -f "$T/target/home/me/debsway/start.sh"
check "...with scripts runnable and files writable again" \
    bash -c '[ "$(stat -c %a "$1/start.sh")" = 755 ] && [ "$(stat -c %a "$1/bin/keys")" = 755 ] && [ "$(stat -c %a "$1/README.md")" = 644 ]' _ "$T/target/home/me/debsway"
check "...owned by the new user" grep -qx 'in-target chown -R me:me /home/me/debsway' "$T/intarget"
check "your own scripts go to ~/scripts" test -f "$T/target/home/me/scripts/mine.txt"
check "a bad user name is refused" not env PATH="$T/fake:$PATH" sh "$L" '../x'
chmod -R u+w "$T/cdrom"

# ---- trying the image in a VM (tools/try-install-iso.sh), its commands only ----
TRY=$HERE/tools/try-install-iso.sh
q=$(XDG_CACHE_HOME=$T/cache bash "$TRY" --print --iso /x/my.iso)
inst=$(sed -n '/^# the installer:/{n;p}' <<<"$q")
booted=$(sed -n '/^# the installed system:/{n;p}' <<<"$q")
check "VM: the image is plugged in as a USB stick, read-only, and started first" \
    bash -c 'grep -qF -- "-drive if=none,id=stick,format=raw,readonly=on,file=/x/my.iso" <<<"$1" && grep -qF -- "-device usb-storage,drive=stick,bootindex=0" <<<"$1"' _ "$inst"
check "...with UEFI, as on a laptop (the firmware read-only, its settings a copy)" \
    bash -c 'grep -qF "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd" <<<"$1" && grep -qF "if=pflash,format=raw,file=$2/debsway/iso-test/vars.fd" <<<"$1"' _ "$inst" "$T/cache"
check "...and one empty disk, in the user's cache folder" \
    bash -c 'grep -qF "if=none,id=disk,file=$2/debsway/iso-test/disk.qcow2" <<<"$1" && ! grep -q disk2 <<<"$1"' _ "$inst" "$T/cache"
check "VM: when the installer restarts at the end, QEMU stops (not the stick again)" grep -qF -- ' -no-reboot' <<<"$inst"
check "...but the installed system can restart normally" not grep -qF -- '-no-reboot' <<<"$booted"
check "VM: the installed system starts without the stick" bash -c '[ -n "$1" ] && ! grep -q stick <<<"$1"' _ "$booted"
check "VM: --two-disks adds a second disk (the installer should then ask)" \
    test "$(XDG_CACHE_HOME=$T/cache bash "$TRY" --print --two-disks --iso /x/my.iso | grep -c 'id=disk2,file=')" = 2
check "VM: a missing image is refused" not env XDG_CACHE_HOME="$T/cache" bash "$TRY" --iso "$T/nothing.iso"
check "VM: an unknown option is refused" not bash "$TRY" --frobnicate
mkdir -p "$T/cache/debsway/iso-test" && echo x >"$T/cache/debsway/iso-test/disk.qcow2"
XDG_CACHE_HOME=$T/cache bash "$TRY" --clean </dev/null >/dev/null 2>&1
check "VM: --clean deletes the VM's files" test ! -e "$T/cache/debsway/iso-test"
check "...and removes QEMU only through its own marker package" \
    bash -c 'grep -q "is_installed \"\$(apt_marker)\"" "$1" && grep -q "apt_purge" "$1"' _ "$TRY"

[ "$fails" -eq 0 ]
