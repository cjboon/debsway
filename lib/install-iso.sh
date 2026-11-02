# shellcheck shell=bash
# lib/install-iso.sh: the pieces of prep/make-install-iso.sh that a test can
# run: which Debian image, filling in the installer's answers, and the boot
# menu edits. Sourced after lib.sh and lib/appimage.sh (its signature checks).
# The Debian CD signing key is pinned in pins.sh (DEBIAN_CD_FPR).

# The image it starts from: Debian's live "standard" (text-only) image, whose
# installer copies the live system onto the disk
DEBIAN_LIVE_BASE=https://cdimage.debian.org/debian-cd/current-live/amd64/iso-hybrid

# live_name SHA512SUMS: the live "standard" (text-only) image's file name in a
# (verified) list
live_name() {
    sed -nE 's/^[0-9a-f]{128}  (debian-live-[0-9]+(\.[0-9]+)+-amd64-standard\.iso)$/\1/p' "$1" | head -1
}

# The kernel arguments that start the automatic install
AUTO_ARGS="auto=true priority=critical preseed/file=/cdrom/debsway-install/preseed.cfg"

# debian_cd_image_ok SHA512SUMS FILE NAME:
# FILE's SHA-512 is the one the list gives for NAME.
# SHA512SUMS must already have been signature-verified.
debian_cd_image_ok() {
    local name=$3 want
    want=$(awk -v n="$name" '$2 == n { print $1; exit }' "$1")
    [ -n "$want" ] &&
        printf '%s  %s\n' "$want" "$2" |
        sha512sum -c --quiet - >/dev/null 2>&1
}

# fill_preseed TEMPLATE USER LOCALE KEYMAP ERASE(true|false) [TIMEZONE]
# [METHOD]: the answers, with the @...@ values in (each already checked by the
# caller). METHOD is crypto (encrypted LVM, the default) or regular (--noencrypt).
fill_preseed() {
    sed -e "s|@USERNAME@|$2|g" -e "s|@LOCALE@|$3|g" -e "s|@KEYMAP@|$4|g" -e "s|@ERASE@|$5|g" \
        -e "s|@TIMEZONE@|${6:-UTC}|g" -e "s|@METHOD@|${7:-crypto}|g" "$1"
}

# autologin_conf USER: the getty drop-in that logs USER in on tty1 without a
# password (data/autologin-getty.conf), for extras/autologin.sh and the stick
autologin_conf() {
    user_ok "$1" || return 1
    sed "s|@USER@|$1|g" "$DEBSWAY_DIR/data/autologin-getty.conf"
}

# this_timezone: the time zone of the computer building the image (UTC if it
# can't be told). DEBSWAY_ETC is where /etc is, for tests.
this_timezone() {
    local etc=${DEBSWAY_ETC:-/etc} tz=
    if [ -L "$etc/localtime" ]; then tz=$(readlink "$etc/localtime"); tz=${tz#*/zoneinfo/}; fi
    [ -n "$tz" ] || tz=$(cat "$etc/timezone" 2>/dev/null) || true
    case $tz in Etc/UTC | Etc/UCT | UCT | Zulu | Etc/Zulu | Universal | Etc/Universal | '') tz=UTC ;; esac
    if timezone_ok "$tz"; then echo "$tz"; else echo UTC; fi
}

# user_ok NAME, locale_ok LOCALE, keymap_ok KEYMAP: values safe to put in the answers
user_ok() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$1" != root ]; }
locale_ok() { [[ $1 =~ ^[a-z]{2,3}_[A-Z]{2}\.UTF-8$ ]]; }
keymap_ok() { [[ $1 =~ ^[a-z]{2,3}(\([a-z0-9_-]+\))?$ ]]; }
# timezone_ok ZONE: UTC, or Area/City (Area/Sub/City) as tzdata names them
timezone_ok() { [ "$1" = UTC ] || [[ $1 =~ ^[A-Z][A-Za-z_]+(/[A-Za-z0-9_+-]+){1,2}$ ]]; }

# grub_add_entry GRUB.CFG: a first menu entry (so the default) that starts
# the automatic install. The live entries stay. Fails if the file doesn't look
# as expected.
grub_add_entry() {
    local f=$1 tmp
    grep -q '^menuentry "Live system (amd64)"' "$f" || return 1
    grep -q '^source[[:space:]]*/boot/grub/install_start.cfg' "$f" || return 1
    tmp=$(mktemp)
    awk -v args="$AUTO_ARGS" '
        !done && /^menuentry / {
            print "menuentry --hotkey=d '"'"'Automatic install with debsway (asks for your passphrase and password)'"'"' {"
            print "    set background_color=black"
            print "    linux    /install/gtk/vmlinuz vga=788 " args " --- quiet"
            print "    initrd   /install/gtk/initrd.gz"
            print "}"
            done = 1
        }
        { print }' "$f" >"$tmp" && cat "$tmp" >"$f"
    rm -f "$tmp"
}

# isolinux_entry: the BIOS menu's entry for it (isolinux/debsway.cfg), the default
isolinux_entry() {
    printf '%s\n' 'label debsway' \
        '	menu label Automatic install with ^debsway (asks for your passphrase and password)' \
        '	menu default' '	kernel /install/gtk/vmlinuz' \
        "	append vga=788 initrd=/install/gtk/initrd.gz $AUTO_ARGS --- quiet"
}

# isolinux_edit MENU.CFG LIVE.CFG: the BIOS menu includes debsway.cfg
# before the live entries, and the live system is no longer the default (its
# entries stay)
isolinux_edit() {
    local menu=$1 live=$2 tmp
    grep -qx 'include live.cfg' "$menu" && grep -qx '	menu default' "$live" || return 1
    tmp=$(mktemp)
    awk '$0 == "include live.cfg" && !done { print "include debsway.cfg"; done = 1 } { print }' "$menu" >"$tmp" && cat "$tmp" >"$menu"
    grep -vx -e '	menu default' "$live" >"$tmp" && cat "$tmp" >"$live"
    rm -f "$tmp"
}

# md5_update MD5SUM.TXT ROOT FILE...: each FILE (a path on the ISO, like
# ./boot/grub/grub.cfg, found under ROOT) gets its new MD5 in the list, so the
# installer's "check the medium" still passes
md5_update() {
    local list=$1 root=$2 f sum tmp
    shift 2
    tmp=$(mktemp)
    cp "$list" "$tmp"
    for f in "$@"; do
        sum=$(md5sum "$root/${f#./}" | cut -d' ' -f1)
        awk -v f="$f" '$2 != f' "$tmp" >"$tmp.n" && mv "$tmp.n" "$tmp"
        echo "$sum  $f" >>"$tmp"
    done
    cat "$tmp" >"$list"
    rm -f "$tmp"
}
