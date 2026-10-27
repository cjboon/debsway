#!/bin/bash
# SimpleX Chat desktop, the official AppImage from GitHub. Re-run to
# update to the newest release. The download must match the hash list
# signed by SimpleX's release key (build@simplex.chat, SIMPLEX_FPR in pins.sh).
# It's a Java app, and Java's GUI is X11-only, so XWayland is installed.
# Usage: bash simplex-chat.sh [--remove]
# summary: SimpleX Chat desktop (signed AppImage)
# status: opt:simplex
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
need_user

NAME=simplex
FPR=$SIMPLEX_FPR
KEY_URL=$SIMPLEX_KEY_URL
REPO=simplex-chat/simplex-chat
ASSET=simplex-desktop-x86_64.AppImage
# System libraries its bundled Java runtime and media code link to
LIBS=(libx11-6 libx11-xcb1 libxext6 libxi6 libxrender1 libxtst6 libxcb1 libxcb-dri3-0
    libasound2t64 libjack-jackd2-0 libusb-1.0-0 libgl1 libegl1 libgbm1 libdrm2
    libfontconfig1 libfreetype6 libharfbuzz0b libfribidi0 libglib2.0-0t64 libwayland-client0)

if [ "${1:-}" = --remove ]; then
    remove_appimage "$NAME"
    apt_purge
    note "Your chats and profile data are left in place."
    exit
fi

need_xwayland
command -v gpg >/dev/null || apt_install gpg
apt_install "${LIBS[@]}"

say "Checking for the latest SimpleX Chat"
tag=$(latest_github_tag "$REPO")
[ -n "$tag" ] || die "Couldn't find the latest SimpleX release on GitHub."
if [ "$(installed_version "$NAME")" = "$tag" ]; then
    note "SimpleX Chat $tag is already installed."
else
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    url=https://github.com/$REPO/releases/download/$tag
    say "Downloading SimpleX Chat $tag (about 350 MB)"
    wget -q --show-progress -O "$tmp/_sha256sums" "$url/_sha256sums" &&
        wget -q --show-progress -O "$tmp/_sha256sums.asc" "$url/_sha256sums.asc" &&
        wget -q --show-progress -O "$tmp/$ASSET" "$url/$ASSET" ||
        die "Download failed."
    say "Verifying"
    verify_detached "$FPR" "$KEY_URL" "$tmp/_sha256sums.asc" "$tmp/_sha256sums" ||
        die "The hash list isn't signed by SimpleX's release key. Not installing."
    # The signed list names files as TAG/NAME
    check_sha256 "$tmp/_sha256sums" "$tag/$ASSET" "$tmp/$ASSET" || die "Not installing."
    note "Signature and checksum are good."
    install_appimage "$NAME" "$tmp/$ASSET" "$tag"
fi
write_launcher "$NAME" simplex-chat.sh AppRun
