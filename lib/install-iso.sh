# shellcheck shell=bash
# lib/install-iso.sh: the pieces of prep/make-install-iso.sh that a test can
# run: which Debian image, filling in the installer's answers, and the boot
# menu edits. Sourced after lib.sh and lib/appimage.sh (its signature checks).
# The Debian CD signing key is pinned in pins.sh (DEBIAN_CD_FPR).

DEBIAN_CD_BASE=https://cdimage.debian.org/debian-cd/current/amd64/iso-cd
# The kernel arguments that start the automatic install
AUTO_ARGS="auto=true priority=critical preseed/file=/cdrom/debsway-install/preseed.cfg"

# netinst_name SHA512SUMS: the netinst image's file name in a (verified) list
netinst_name() {
    sed -nE 's/^[0-9a-f]{128}  (debian-[0-9]+(\.[0-9]+)+-amd64-netinst\.iso)$/\1/p' "$1" | head -1
}

# netinst_ok SHA512SUMS FILE NAME: FILE's SHA-512 is the one the list gives
# for the image NAME (FILE may still be the download, NAME.part)
netinst_ok() {
    local name=$3 want
    want=$(awk -v n="$name" '$2 == n { print $1; exit }' "$1")
    [ -n "$want" ] && echo "$want  $2" | sha512sum -c --quiet - >/dev/null 2>&1
}

# fill_preseed TEMPLATE USER LOCALE KEYMAP ERASE(true|false): the answers, with
# the @...@ values in (each already checked by the caller)
fill_preseed() {
    sed -e "s|@USERNAME@|$2|g" -e "s|@LOCALE@|$3|g" -e "s|@KEYMAP@|$4|g" -e "s|@ERASE@|$5|g" "$1"
}

# user_ok NAME, locale_ok LOCALE, keymap_ok KEYMAP: values safe to put in the answers
user_ok() { [[ $1 =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && [ "$1" != root ]; }
locale_ok() { [[ $1 =~ ^[a-z]{2,3}_[A-Z]{2}\.UTF-8$ ]]; }
keymap_ok() { [[ $1 =~ ^[a-z]{2,3}(\([a-z0-9_-]+\))?$ ]]; }

# grub_add_entry GRUB.CFG: a first menu entry (so the default) that starts the
# automatic, graphical install. The others, rescue mode included, are left as
# they are. Fails if the file doesn't look as expected.
grub_add_entry() {
    local f=$1 tmp
    grep -q "^menuentry --hotkey=g 'Graphical install' {" "$f" || return 1
    grep -q '/install.amd/gtk/initrd.gz' "$f" || return 1
    tmp=$(mktemp)
    awk -v args="$AUTO_ARGS" '
        !done && /^menuentry / {
            print "menuentry --hotkey=a '"'"'Automatic install with debsway (asks for your passphrase and password)'"'"' {"
            print "    set background_color=black"
            print "    linux    /install.amd/vmlinuz vga=788 " args " --- quiet"
            print "    initrd   /install.amd/gtk/initrd.gz"
            print "}"
            done = 1
        }
        { print }' "$f" >"$tmp" && cat "$tmp" >"$f"
    rm -f "$tmp"
}

# isolinux_entry: the BIOS menu's entry for it (isolinux/debsway.cfg), the default
isolinux_entry() {
    printf '%s\n' 'label debsway' \
        '	menu label ^Automatic install with debsway (asks for your passphrase and password)' \
        '	menu default' '	kernel /install.amd/vmlinuz' \
        "	append vga=788 initrd=/install.amd/gtk/initrd.gz $AUTO_ARGS --- quiet"
}

# isolinux_edit MENU.CFG GTK.CFG: the BIOS menu includes debsway.cfg first, and
# the graphical install is no longer the default (its entry stays)
isolinux_edit() {
    local menu=$1 gtk=$2 tmp
    grep -qx 'include gtk.cfg' "$menu" && grep -qx 'default installgui' "$gtk" && grep -qx '	menu default' "$gtk" || return 1
    tmp=$(mktemp)
    awk '$0 == "include gtk.cfg" && !done { print "include debsway.cfg"; done = 1 } { print }' "$menu" >"$tmp" && cat "$tmp" >"$menu"
    grep -vx -e 'default installgui' -e '	menu default' "$gtk" >"$tmp" && cat "$tmp" >"$gtk"
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
