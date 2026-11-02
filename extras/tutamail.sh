#!/bin/bash
# Tuta Mail desktop (Tuta, formerly Tutanota: end-to-end encrypted email), the
# official AppImage from app.tuta.com. Re-run to update to the newest release.
# Tuta signs it with openssl, not gpg: the signature must be from Tuta's
# code-signing key (data/tuta-pub.pem, TUTA_KEY_SHA256 in pins.sh), and the
# unpacked app must be the version Tuta's release file names, no older than the
# one installed. It's an Electron app and runs on Wayland directly.
# Usage: bash tutamail.sh [--remove]
# summary: Tuta Mail desktop (signed AppImage)
# status: opt:tuta
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
need_user

NAME=tuta
KEY=$DEBSWAY_DIR/data/tuta-pub.pem
URL=$TUTA_DESKTOP_URL
ASSET=tutanota-desktop-linux.AppImage
# The system libraries its Electron binary links to (readelf -d), and
# xdg-open for links in mails. libsecret: Tuta keeps a saved login only in a
# keyring (the Seahorse extra's), never in a plain file.
LIBS=(libnss3 libnspr4 libglib2.0-0t64 libatk1.0-0t64 libatk-bridge2.0-0t64 libatspi2.0-0t64
    libcups2t64 libdbus-1-3 libcairo2 libgtk-3-0t64 libpango-1.0-0 libx11-6 libxcomposite1
    libxdamage1 libxext6 libxfixes3 libxrandr2 libxcb1 libxkbcommon0 libgbm1 libexpat1 libudev1
    libasound2t64 libsecret-1-0 xdg-utils)

if [ "${1:-}" = --remove ]; then
    remove_appimage "$NAME"
    apt_purge
    note "Your mail settings and the app's data are left in ~/.config/tutanota-desktop."
    exit
fi

need_tools openssl:openssl wget:wget
apt_install "${LIBS[@]}"

# tuta_version FILE: the version Tuta's release file (latest-linux.yml) names
tuta_version() {
    sed -n 's/^version: *\([^ ]*\) *$/\1/p' "$1" | head -1
}

# tuta_is_version DIR: the unpacked app is $version. The release file isn't
# signed, but the app's package.json (inside resources/app.asar) is, so an old
# signed AppImage can't be passed off as a new one.
tuta_is_version() {
    grep -aqF "\"version\": \"$version\"" "$1/resources/app.asar" && return 0
    warn "The signed app inside isn't version $version, as Tuta's release file says."
    return 1
}

say "Checking for the latest Tuta Mail"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
wget -q -O "$tmp/latest-linux.yml" "$URL/latest-linux.yml" || die "Couldn't reach $URL."
version=$(tuta_version "$tmp/latest-linux.yml")
[[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "Couldn't read the newest version from $URL/latest-linux.yml."
have=$(installed_version "$NAME")
if [ "$have" = "$version" ]; then
    note "Tuta Mail $version is already installed."
elif [ -n "$have" ] && [ "$(printf '%s\n' "$have" "$version" | sort -V | tail -1)" = "$have" ]; then
    die "Tuta's server offers $version, older than the installed $have. Not installing it; try again later."
else
    say "Downloading Tuta Mail $version (about 150 MB)"
    wget -q --show-progress -O "$tmp/linux-sig.bin" "$URL/linux-sig.bin" &&
        wget -q --show-progress -O "$tmp/$ASSET" "$URL/$ASSET" ||
        die "Download failed."
    say "Verifying"
    verify_rsa_sha512 "$TUTA_KEY_SHA256" "$KEY" "$tmp/linux-sig.bin" "$tmp/$ASSET" ||
        die "The AppImage isn't signed by Tuta's code-signing key. Not installing."
    note "The signature is good."
    install_appimage "$NAME" "$tmp/$ASSET" "$version" tuta_is_version
fi
# The binary itself, not AppRun: AppRun quietly adds --no-sandbox when it
# can't make a user namespace, and Electron's sandbox should stay on.
# Wayland directly, so it needs no XWayland.
write_launcher "$NAME" tutamail.sh tutanota-desktop ELECTRON_OZONE_PLATFORM_HINT=wayland
note "Tuta keeps you logged in only with a keyring to store that in. Without one"
note "(bash ~/debsway/extras/seahorse.sh), you log in at every start."
note "Updates: run this script again; bash ~/debsway/test.sh says when one is out."
