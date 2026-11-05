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
# Usage: bash tails-usb.sh            set up tails-usb, and say how to use it
#        bash tails-usb.sh --make     make a stick (what tails-usb runs)
#        bash tails-usb.sh --remove
#        bash tails-usb.sh --manual   the steps to make a stick by hand
# summary: Tails on a USB stick, downloaded and checked
# security: most
# status: bin:tails-usb
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/tails.sh"
. "$WREN_DIR/lib/usb-stick.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
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
    local tmp line v url sha size img sig key i
    tmp=$(mktemp -d)
    # (its name now: tmp is this function's, gone by the time the script exits)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT
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

    stick_write "$img" "$MIN_STICK" "Tails $v"
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
    More: docs/extras/tails-usb.md in the Wren Linux folder.
EOF
}

case ${1:-} in
    --make)
        for c in wget gpg python3 lsblk; do command -v "$c" >/dev/null || die "$c is missing. Run: bash $WREN_DIR/extras/tails-usb.sh"; done
        make_stick ;;
    "")
        setup
        cat <<'EOF'

    tails-usb is set up. To make a Tails stick:

    1. Have a USB stick of 8 GB or more. Everything on it is erased.
    2. Run in a terminal:  tails-usb   (or Super+d, then tails-usb)
    3. It downloads the newest Tails (through Tor if Tor runs here, else it
       asks first), checks its signature, and keeps the checked copy for the
       next stick.
    4. Plug the stick in when it asks, pick it from the list, and type its
       name to confirm. It writes Tails and reads it back to check.
    5. When it is done it says how to start the computer from the stick.

    More: docs/extras/tails-usb.md in the Wren Linux folder.
EOF
        pause_if_asked ;;
    *) die "Usage: bash extras/tails-usb.sh [--make | --remove]" ;;
esac
