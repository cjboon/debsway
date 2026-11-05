#!/bin/bash
# get-iso: downloads another system's install image and checks it, then offers
# to write it to a USB stick. It sets up the command get-iso, which:
#  - offers Debian, Tails, Kicksecure, Qubes OS, Kali, Parrot (Security and Home) and Arch;
#  - finds the newest release in the project's own release list or folder;
#  - downloads it through Tor when Tor runs here (apt over Tor, remote access,
#    the onion site), so your network can't see what you fetch; otherwise it
#    asks before downloading directly;
#  - keeps it only if it is that newest release and its own signature, or a
#    signed list of checksums naming it, is by the project's key pinned in
#    pins.sh (a download that fails is deleted);
#  - keeps the checked image in ~/ISOs/NAME (the newest only), checked again
#    before every use, for a VM in virt-manager or the next stick;
#  - if you say so, lists only USB sticks, never the disk this system runs
#    from, asks you to type the stick's name, writes it, and reads it back.
# Nothing it fetches is run here. Writing a stick erases everything on it.
# Usage: bash get-iso.sh            set up get-iso
#        bash get-iso.sh --get [NAME]   what get-iso runs (NAME: see --list)
#        bash get-iso.sh --list
#        bash get-iso.sh --remove
#        bash get-iso.sh --manual   the steps to do it by hand
# summary: Other systems' images, checked, onto a USB stick
# security: most
# status: bin:get-iso
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$WREN_DIR/lib/appimage.sh"
. "$WREN_DIR/lib/tails.sh"
. "$WREN_DIR/lib/usb-stick.sh"
. "$WREN_DIR/lib/get-iso.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

ISOS=${WREN_ISO_DIR:-$HOME/ISOs}

if [ "${1:-}" = --remove ]; then
    remove_bin get-iso
    apt_purge
    if [ -d "$ISOS" ] && ask "Also delete the images kept in $ISOS?" n; then
        rm -rf "$ISOS"
        note "Deleted."
    fi
    note "Sticks you made keep working."
    exit
fi

if [ "${1:-}" = --list ]; then
    while IFS=$'\t' read -r name what; do printf '  %-16s %s\n' "$name" "$what"; done <<<"$ISO_LIST"
    exit 0
fi

# pick: a NAME from the list, asked for by number
pick() {
    local names=() choice name what
    # (on stderr: what this prints on stdout is the answer)
    say "Which system?" >&2
    while IFS=$'\t' read -r name what; do
        names+=("$name")
        printf '    %d) %-16s %s\n' "${#names[@]}" "$name" "$what" >&2
    done <<<"$ISO_LIST"
    tty_read choice "Which (1-${#names[@]})? "
    [[ $choice =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#names[@]} ] || die "None chosen; nothing was downloaded."
    echo "${names[choice - 1]}"
}

get() {
    local name=$1 tmp v url algo sum file dir img i min
    tmp=$(mktemp -d)
    # (its name now: tmp is this function's, gone by the time the script exits)
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp'" EXIT

    say "How to download"
    if [ -n "${WREN_ISO_MIRROR:-}" ]; then
        :
    elif systemctl is-active --quiet tor@default.service && command -v torsocks >/dev/null; then
        ISO_VIA_TOR=true
        note "Through Tor (the system tor service runs here): your network won't see what you fetch."
    else
        note "Tor doesn't run here, so your network would see which system you download"
        note "(not what you do with it later). Set up apt over Tor first (bash parts/apt-tor.sh)"
        note "to download through Tor instead."
        ask "Download directly?" y || die "Nothing was downloaded."
    fi

    say "The newest $name"
    iso_release "$name" "$tmp" || die "Nothing was downloaded."
    read -r v url algo sum <"$tmp/release"
    file=${url##*/}
    [[ $file =~ ^[A-Za-z0-9._+-]+$ ]] || die "The image's name ($file) isn't one get-iso expects."
    dir=$ISOS/$name
    img=$dir/$file
    note "$name $v: $file"

    if [ -f "$img" ] && iso_ok "$img" "$tmp" 2>/dev/null; then
        note "Using the copy kept here, checked again: $img"
    else
        mkdir -p "$dir"
        say "Downloading $file"
        if ! iso_fetch "$url" "$img.part"; then
            [ "$(df -Pm "$dir" | awk 'NR == 2 { print $4 }')" -ge 64 ] ||
                die "The disk is full ($dir): make room, then run get-iso $name again to go on where it stopped."
            die "The download didn't finish; run get-iso $name again to go on where it stopped."
        fi
        say "Checking it"
        if ! iso_ok "$img.part" "$tmp"; then
            rm -f "$img.part"
            die "The download didn't pass the checks, so it was deleted."
        fi
        mv "$img.part" "$img"
        # Keep only the newest
        for i in "$dir"/*; do
            [ "$i" = "$img" ] || rm -f "$i"
        done
        note "Checked against $name's pinned key, and the newest release: $img"
    fi

    ask "Write it to a USB stick now (everything on the stick is erased)?" n || {
        note "Kept in $img. For a stick later: get-iso $name"
        return 0
    }
    # The image, and a little room: sticks sold as 8 GB hold a little less
    min=$(stat -c %s "$img")
    [ "$name" != tails ] || min=$((7500 * 1000 * 1000))
    stick_write "$img" "$min" "$name $v"
    note "Written and read back: the stick holds exactly the checked image."
    note "To start from it: plug it in, start the computer, and pick the stick in the boot"
    note "menu (often F12, F9, F10, F11 or Esc; on a Mac hold Option)."
}

case ${1:-} in
    --get)
        for c in wget gpg python3 lsblk; do command -v "$c" >/dev/null || die "$c is missing. Run: bash $WREN_DIR/extras/get-iso.sh"; done
        name=${2:-}
        [ -n "$name" ] || name=$(pick)
        grep -qx -- "$name" <<<"$(iso_names)" || die "get-iso doesn't know \"$name\". It knows: $(iso_names | paste -sd' ')"
        get "$name" ;;
    "")
        say "Installing what get-iso needs"
        # torsocks: the download through Tor; python3: reading Arch's and Tails' release lists
        apt_install wget gpg python3 torsocks util-linux
        install_bin get-iso
        note "get-iso is set up. Run: get-iso   (or get-iso NAME; get-iso --list names them)"
        pause_if_asked ;;
    *) die "Usage: bash extras/get-iso.sh [--get [NAME] | --list | --remove | --manual]" ;;
esac
