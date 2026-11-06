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

# debian_live_source IMAGE-NAME DIR: Debian's source for that live image, for that exact
# version, into DIR (the .tar and .contents): the GPL asks whoever hands out an image to
# offer its source too. Debian keeps the newest in current-live and older ones in its archive.
# Only files with the checksum in a list the Debian CD signing key signed are kept. A
# saved copy that still checks out isn't fetched again. (WREN_WGET: a test's pretend wget)
debian_live_source() {
    local name=$1 dir=$2 ver stem where url f list ok=false site=https://cdimage.debian.org
    [[ $name =~ ^debian-live-([0-9]+(\.[0-9]+)+)-amd64-standard\.iso$ ]] || {
        warn "\"$name\" isn't the name of a Debian live image."
        return 1
    }
    ver=${BASH_REMATCH[1]} stem=debian-live-$ver-source-standard
    list=$(mktemp -d)
    for where in debian-cd/current-live cdimage/archive/$ver-live; do
        url=$site/$where/source/tar
        "${WREN_WGET:-wget}" -q -O "$list/SHA512SUMS" "$url/SHA512SUMS" &&
            "${WREN_WGET:-wget}" -q -O "$list/SHA512SUMS.sign" "$url/SHA512SUMS.sign" || continue
        if ! verify_detached "$DEBIAN_CD_FPR" "$DEBIAN_CD_KEY_URL" "$list/SHA512SUMS.sign" "$list/SHA512SUMS"; then
            warn "Debian's list of source checksums at $where isn't signed by the Debian CD signing key."
            rm -rf "$list"
            return 1
        fi
        # (current-live has moved on from this version: its archive is next)
        grep -qE "^[0-9a-f]{128}  $stem\.tar\$" "$list/SHA512SUMS" || continue
        ok=true
        break
    done
    if ! $ok; then
        warn "Couldn't find the source of Debian $ver at $site."
        rm -rf "$list"
        return 1
    fi
    for f in "$stem.tar" "$stem.contents"; do
        if [ -f "$dir/$f" ] && debian_cd_image_ok "$list/SHA512SUMS" "$dir/$f" "$f"; then continue; fi
        "${WREN_WGET:-wget}" -q --show-progress -c -O "$dir/$f.part" "$url/$f" || {
            warn "The download of $f didn't finish; run this again to go on."
            rm -rf "$list"
            return 1
        }
        if ! debian_cd_image_ok "$list/SHA512SUMS" "$dir/$f.part" "$f"; then
            rm -f "$dir/$f.part"
            warn "$f doesn't have the checksum in Debian's signed list, so it was deleted."
            rm -rf "$list"
            return 1
        fi
        mv "$dir/$f.part" "$dir/$f"
    done
    rm -rf "$list"
}

# The kernel arguments that start the automatic install
AUTO_ARGS="auto=true priority=critical preseed/file=/cdrom/wren-install/preseed.cfg"

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

# offline_debs_refresh: the Wi-Fi packages that go on the stick (offline/debs),
# for a laptop with no network at first boot, brought up to date when wifi.sh
# would refuse them within WREN_OFFLINE_MIN_DAYS days (5): their signed
# lists are fetched again and the saved packages checked against them (--check);
# if one has changed, the same firmware is fetched again; with none saved,
# every common Wi-Fi card's (the laptop it's for may not be this one). Says
# until when they're good. Never stops the build: a stick still installs over
# a cable or a phone.
offline_debs_refresh() {
    local debs=${OFFLINE_DIR:-$WREN_DIR/offline}/debs fetch=$WREN_DIR/prep/fetch-offline-debs.sh
    local now until min=${WREN_OFFLINE_MIN_DAYS:-5} fw=() f
    now=${WREN_NOW:-$(date +%s)}
    until=$(offline_good_until "$debs/verify")
    if [ -z "$until" ] || [ "$until" -lt $((now + min * 86400)) ]; then
        if [ -f "$debs/Packages" ]; then
            note "Refreshing the offline Wi-Fi packages' signed lists (they'd soon be too old to use)."
            if ! bash "$fetch" --check; then
                for f in "$debs"/firmware-*_*.deb; do [ -f "$f" ] && fw+=("$(basename -- "${f%%_*}")"); done
                note "Fetching them again${fw[*]:+ (with ${fw[*]})}."
                bash "$fetch" "${fw[@]}" || warn "Couldn't fetch them again."
            fi
        else
            note "Fetching the offline Wi-Fi packages, with firmware for every common card."
            bash "$fetch" --all || warn "Couldn't fetch them."
        fi
        until=$(offline_good_until "$debs/verify")
    fi
    if [ -z "$until" ]; then
        warn "No offline Wi-Fi packages on this stick: the new laptop needs a cable or a phone to get online."
    elif [ "$until" -lt "$now" ]; then
        warn "The offline Wi-Fi packages are too old to be used: the new laptop needs a cable or a phone to get online."
    else
        note "The offline Wi-Fi packages on it work until $(date -d "@$until" '+%F') (after that wifi.sh refuses them as too old)."
    fi
}

# autologin_conf USER: the getty drop-in that logs USER in on tty1 without a
# password (data/autologin-getty.conf), for extras/autologin.sh and the stick
autologin_conf() {
    user_ok "$1" || return 1
    sed "s|@USER@|$1|g" "$WREN_DIR/data/autologin-getty.conf"
}

# this_timezone: the time zone of the computer building the image (UTC if it
# can't be told). WREN_ETC is where /etc is, for tests.
this_timezone() {
    local etc=${WREN_ETC:-/etc} tz=
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
            print "menuentry --hotkey=d '"'"'Automatic install with Wren Linux (asks for your passphrase and password)'"'"' {"
            print "    set background_color=black"
            print "    linux    /install/gtk/vmlinuz vga=788 " args " --- quiet"
            print "    initrd   /install/gtk/initrd.gz"
            print "}"
            done = 1
        }
        { print }' "$f" >"$tmp" && cat "$tmp" >"$f"
    rm -f "$tmp"
}

# isolinux_entry: the BIOS menu's entry for it (isolinux/wren.cfg), the default
isolinux_entry() {
    printf '%s\n' 'label Wren Linux' \
        '	menu label Automatic install with ^Wren Linux (asks for your passphrase and password)' \
        '	menu default' '	kernel /install/gtk/vmlinuz' \
        "	append vga=788 initrd=/install/gtk/initrd.gz $AUTO_ARGS --- quiet"
}

# isolinux_edit MENU.CFG LIVE.CFG: the BIOS menu includes wren.cfg
# before the live entries, and the live system is no longer the default (its
# entries stay)
isolinux_edit() {
    local menu=$1 live=$2 tmp
    grep -qx 'include live.cfg' "$menu" && grep -qx '	menu default' "$live" || return 1
    tmp=$(mktemp)
    awk '$0 == "include live.cfg" && !done { print "include wren.cfg"; done = 1 } { print }' "$menu" >"$tmp" && cat "$tmp" >"$menu"
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
