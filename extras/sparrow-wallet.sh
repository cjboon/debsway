#!/bin/bash
# Sparrow Wallet (Bitcoin), the official .deb from its GitHub releases.
# Better privacy tools than Electrum (coin control, built-in Tor) and good
# hardware wallet support. The download is checked against the release's
# signed list of SHA-256 sums, from Craig Raw's key. Sparrow is a JavaFX
# app, which is X11-only, so XWayland is installed.
# Running it again installs a newer release if there is one.
# Usage: bash sparrow-wallet.sh [--remove]
# summary: Sparrow Bitcoin wallet (signed .deb)
# status: apt:sparrowwallet
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/appimage.sh"
need_user

# Craig Raw's key: SPARROW_FPR and SPARROW_KEY_URL in pins.sh

if [ "${1:-}" = --remove ]; then
    apt_purge sparrowwallet
    remove_bin sparrow
    note "Your wallets are kept in ~/.sparrow. Back them up before deleting anything."
    exit
fi

say "Checking the newest Sparrow"
version=$(latest_github_tag sparrowwallet/sparrow)
[[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "Couldn't read the newest version from GitHub."
installed=$(dpkg-query -W -f='${Version}' sparrowwallet 2>/dev/null || true)
if [ "${installed%-*}" = "$version" ]; then
    note "Sparrow $version is already installed."
else
    deb="sparrowwallet_$version-1_amd64.deb"
    manifest="sparrow-$version-manifest.txt"
    url="https://github.com/sparrowwallet/sparrow/releases/download/$version"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT
    say "Downloading Sparrow $version"
    wget -q -O "$work/$deb" "$url/$deb" || die "Download failed: $url/$deb"
    wget -q -O "$work/$manifest" "$url/$manifest" || die "Download failed: $url/$manifest"
    wget -q -O "$work/$manifest.asc" "$url/$manifest.asc" || die "Download failed: $url/$manifest.asc"
    verify_detached "$SPARROW_FPR" "$SPARROW_KEY_URL" "$work/$manifest.asc" "$work/$manifest" ||
        die "The signature on Sparrow's checksum list didn't check out. Not installing."
    check_sha256 "$work/$manifest" "$deb" "$work/$deb" || die "Not installing."
    note "Signature and checksum OK."
    need_xwayland
    # apt reads the local file as the _apt user, which can't enter mktemp dirs
    chmod 755 "$work"
    chmod 644 "$work/$deb"
    apt_install "$work/$deb"
fi

# The package puts Sparrow in /opt without a command on PATH
install_bin sparrow
note "Run it with: sparrow   (or Super+d). Wallets live in ~/.sparrow."
note "On first start it asks which server to use. A public server sees your wallet's"
note "addresses; Sparrow's Tor (proxy) setting hides your IP address from it, and"
note "your own Bitcoin node is the most private."
