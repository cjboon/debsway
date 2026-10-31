#!/bin/bash
# Feather Wallet (Monero), the official AppImage from featherwallet.org.
# Re-run to update to the newest release. The download must match the
# hash list signed by Feather's key (FEATHER_FPR in pins.sh).
# Feather forces X11 itself (QT_QPA_PLATFORM=xcb), so XWayland is installed.
# Usage: bash feather-wallet.sh [--remove]
# summary: Feather Monero wallet (signed AppImage)
# status: opt:feather
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
need_user

NAME=feather
FPR=$FEATHER_FPR
KEY_URL=$FEATHER_KEY_URL
FILES=https://featherwallet.org/files/releases

if [ "${1:-}" = --remove ]; then
    remove_appimage "$NAME"
    apt_purge
    note "Your wallet files are left where you saved them."
    exit
fi

need_xwayland
command -v gpg >/dev/null || apt_install gpg

say "Checking for the latest Feather"
version=$(latest_github_tag feather-wallet/feather)
# Feather's releases are plain numbers (2.8.1); anything else is refused
[[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "Couldn't find the latest Feather version on GitHub (or it didn't look like one)."
if [ "$(installed_version "$NAME")" = "$version" ]; then
    note "Feather $version is already installed."
else
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    file=feather-$version.AppImage
    say "Downloading Feather $version"
    wget -q --show-progress -O "$tmp/hashes.txt" "$FILES/hashes-$version.txt" &&
        wget -q --show-progress -O "$tmp/$file" "$FILES/linux-appimage/$file" ||
        die "Download failed."
    say "Verifying"
    verify_clearsigned "$FPR" "$KEY_URL" "$tmp/hashes.txt" "$tmp/sums.txt" ||
        die "The hash list isn't signed by Feather's key. Not installing."
    check_sha256 "$tmp/sums.txt" "$file" "$tmp/$file" || die "Not installing."
    note "Signature and checksum are good."
    install_appimage "$NAME" "$tmp/$file" "$version"
fi
# Their AppRun only works under the AppImage runtime; run the binary the
# way it would, X11 included
write_launcher "$NAME" feather-wallet.sh usr/bin/feather QT_QPA_PLATFORM=xcb
