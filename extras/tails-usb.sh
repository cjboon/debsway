#!/bin/bash
# Tails on a USB stick. Tails is a whole operating system that runs from a USB
# stick, sends everything through Tor and forgets everything when you shut it
# down. This sets up a command, tails-usb, that:
#  - finds the newest Tails in Tails' own release file, and downloads the USB
#    image through Tor when Tor runs here (apt over Tor, remote access, the
#    onion site), so your network can't see you fetch it; otherwise it asks
#    before downloading directly;
#  - uses the image only if its signature is the Tails signing key's (pinned
#    in pins.sh, TAILS_FPR) and it is exactly the image the release file names
#    for the newest version (so an older, signed Tails isn't slipped in);
#  - keeps that verified copy in offline/tails (the newest only), checked again
#    before every use, so the next stick needs no download;
#  - lists only USB sticks, never the disk this system runs from, asks you to
#    type the stick's name, writes Tails onto it, and reads it back to check;
#  - says how to start and use it (docs/extras/tails-usb.md has more).
# Writing a stick erases everything on it, Persistent Storage included.
# Usage: bash tails-usb.sh            set up tails-usb, and offer to make a stick
#        bash tails-usb.sh --make     make a stick (what tails-usb runs)
#        bash tails-usb.sh --remove
# summary: Tails on a USB stick, downloaded and checked
# status: bin:tails-usb
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
. "$DEBSWAY_DIR/lib/tails.sh"
need_user

MIN_STICK=$((7500 * 1000 * 1000))   # Tails asks for 8 GB; sticks sold as 8 GB hold a little less

if [ "${1:-}" = --remove ]; then
    remove_bin tails-usb
    apt_purge torsocks
    if [ -d "$TAILS_OFFLINE" ] && ask "Also delete the saved Tails image in $TAILS_OFFLINE?" n; then
        rm -rf "$TAILS_OFFLINE"
        note "Deleted."
    fi
    note "Sticks you made keep working; Tails updates itself."
    exit
fi

setup() {
    say "Installing what tails-usb needs"
    # torsocks: the download through Tor; python3: reading Tails' release file
    apt_install wget gpg python3 torsocks util-linux
    install_bin tails-usb
}

# fetch URL FILE: through Tor when this computer runs it, else as decided below
VIA_TOR=false
fetch() {
    if $VIA_TOR; then torsocks wget -q --show-progress -c -O "$2" "$1"; else wget -q --show-progress -c -O "$2" "$1"; fi
}

make_stick() {
    local tmp line v url sha size img sig key i choice name dev bytes model
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$TAILS_OFFLINE"

    say "How to download"
    if systemctl is-active --quiet tor@default.service && command -v torsocks >/dev/null; then
        VIA_TOR=true
        note "Through Tor (the system tor service runs here): your network won't see you fetch Tails."
    else
        note "Tor doesn't run here, so your network would see you download Tails from tails.net"
        note "(not what you do with it later). Set up apt over Tor first (bash parts/apt-tor.sh)"
        note "to download through Tor instead."
        ask "Download directly?" y || die "Nothing was downloaded."
    fi

    say "The newest Tails"
    if fetch "$TAILS_LATEST_URL" "$tmp/latest.json" 2>/dev/null && line=$(tails_latest "$tmp/latest.json"); then
        read -r v url sha size <<<"$line"
        note "Tails $v ($((size / 1000000)) MB)"
        echo "$line" >"$tmp/release"
    else
        # Offline: the saved copy, with the release details saved next to it
        line=$(cat "$TAILS_OFFLINE"/tails-amd64-*.release 2>/dev/null | sort -V | tail -1)
        [ -n "$line" ] || die "Couldn't read Tails' release file from tails.net, and no saved copy is here."
        read -r v url sha size <<<"$line"
        warn "Couldn't reach tails.net: using the saved Tails $v, which may not be the newest."
    fi
    img=$TAILS_OFFLINE/tails-amd64-$v.img
    sig=$img.sig
    key=$TAILS_OFFLINE/tails-signing.key

    if [ -f "$img" ] && [ -f "$sig" ] && [ -f "$key" ] && tails_image_ok "$img" "$sig" "$key" "$sha" "$size" 2>/dev/null; then
        note "Using the saved copy, checked again: $img"
    else
        say "Downloading Tails $v"
        fetch "$TAILS_KEY_URL" "$key.part" && mv "$key.part" "$key" || die "Couldn't download the Tails signing key."
        fetch "$TAILS_SIG_BASE/tails-amd64-$v.img.sig" "$sig" || die "Couldn't download the signature."
        fetch "$url" "$img.part" || die "The download didn't finish; run tails-usb again to go on where it stopped."
        say "Checking it"
        if ! tails_image_ok "$img.part" "$sig" "$key" "$sha" "$size"; then
            rm -f "$img.part" "$sig"
            die "The download didn't pass the checks, so it was deleted."
        fi
        mv "$img.part" "$img"
        [ ! -f "$tmp/release" ] || cp "$tmp/release" "$TAILS_OFFLINE/tails-amd64-$v.release"
        # Keep only the newest
        for i in "$TAILS_OFFLINE"/tails-amd64-*.img; do
            [ "$i" = "$img" ] || rm -f "$i" "$i.sig" "${i%.img}.release"
        done
        note "Signed by the Tails signing key, and the image Tails' release file names: $img"
    fi

    say "The USB stick"
    mapfile -t disks < <(usb_disks)
    while [ ${#disks[@]} -eq 0 ]; do
        note "No USB stick found. Plug one in (8 GB or more; everything on it will be erased)."
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
    [ "$bytes" -ge "$MIN_STICK" ] || die "$dev holds $((bytes / 1000000000)) GB; Tails needs 8 GB or more. Nothing was written."
    warn "EVERYTHING on $dev ($model, $((bytes / 1000000000)) GB) will be erased."
    tty_read choice "Type its name, $name, to go on: "
    [ "$choice" = "$name" ] || die "That isn't $name; nothing was written."

    # Its partitions may be mounted (USB automount): unmount them first
    while read -r part mnt; do
        [ -n "$mnt" ] || continue
        sudo umount "$part" || die "Couldn't unmount $part ($mnt); close what uses it and run tails-usb again."
    done < <(lsblk -lnpo NAME,MOUNTPOINTS "$dev" | awk 'NF > 1')

    say "Writing Tails $v to $dev (a few minutes)"
    write_and_check "$img" "$dev" || die "Writing didn't work. Try again, or another stick."
    note "Written and read back: the stick holds exactly the checked image."

    cat <<EOF

    Your Tails stick is ready. To use it:

    1. Shut this computer down (or use another one), plug the stick in and
       start it. Open the boot menu with the key your computer shows at start
       (often F12, F9, F10, F11 or Esc; on a Mac hold Option) and pick the
       USB stick. Tails starts with Secure Boot on most computers.
    2. The Welcome Screen: pick your language and keyboard. You don't need
       anything else to begin; an administration password is only for
       installing extra software for that session.
    3. Connect to Tor in the "Tor Connection" window. If your network blocks
       Tor, or must not see that you use it, choose a bridge there.
    4. Everything you do is forgotten when you shut down. To keep files, a
       browser bookmark or Wi-Fi passwords, create the encrypted Persistent
       Storage (Applications > Persistent Storage) with a long passphrase,
       and keep in it only what you need.
    5. When you're done, shut Tails down from the menu: it wipes the memory.

    Tails updates itself when it is connected. If an update can't be done,
    or the stick fails, run tails-usb again to make a fresh one (that erases
    the stick, Persistent Storage included: back that up first).
    Tails' own guide: https://tails.net/doc/
    More: docs/extras/tails-usb.md in the debsway folder.
EOF
}

case ${1:-} in
    --make)
        for c in wget gpg python3 lsblk; do command -v "$c" >/dev/null || die "$c is missing. Run: bash $DEBSWAY_DIR/extras/tails-usb.sh"; done
        make_stick ;;
    "")
        setup
        note "Make a Tails stick any time with: tails-usb"
        if ask "Make one now?" n; then make_stick; fi ;;
    *) die "Usage: bash extras/tails-usb.sh [--make | --remove]" ;;
esac
