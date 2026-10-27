#!/bin/bash
# Run this on a network you don't mind seeing you fetch Tor Browser: it
# talks to torproject.org without Tor. It saves the newest Tor Browser
# and its signature into ./torbrowser, checked against the Tor Browser
# developers' key, so extras/tor-browser.sh can install it later without
# contacting torproject.org. Tor Browser updates itself through Tor once
# it's connected, so an older copy is fine.
#
#   bash fetch-tor-browser.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"
. "$DEBSWAY_DIR/extras/appimage.sh"

# TB_FPR is in pins.sh. Its signing subkeys change every couple of
# years, so the current key is saved next to the download for
# extras/tor-browser.sh to check against offline.
KEY_URL=$TB_KEY_URL
OUT="$DEBSWAY_DIR/torbrowser"
KEY="$OUT/tor-browser-developers.asc"
ARCH=$(uname -m)

[ "$ARCH" = x86_64 ] || die "Tor Browser for Linux is only built for x86_64."
command -v gpg >/dev/null || die "gpg is missing. Install it with: sudo apt install gpg"

say "Checking the newest Tor Browser"
version=$(wget -qO- "https://aus1.torproject.org/torbrowser/update_3/release/download-linux-$ARCH.json" |
    sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1) || true
[[ $version =~ ^[0-9]+(\.[0-9]+)+$ ]] || die "Couldn't read the newest version from torproject.org."
name="tor-browser-linux-$ARCH-$version.tar.xz"
url="https://dist.torproject.org/torbrowser/$version/$name"
note "Newest: $version"

mkdir -p "$OUT"
wget -qO "$KEY.part" "$KEY_URL" || die "Couldn't download the signing key from $KEY_URL"
if [ -f "$OUT/$name" ] && [ -f "$OUT/$name.asc" ] &&
    verify_detached "$TB_FPR" "$KEY.part" "$OUT/$name.asc" "$OUT/$name"; then
    mv "$KEY.part" "$KEY"
    note "Already saved and verified: $OUT/$name"
    exit 0
fi

say "Downloading Tor Browser $version (about 140 MB)"
wget -q -O "$OUT/$name.part" "$url" || die "Download failed: $url"
wget -qO "$OUT/$name.asc.part" "$url.asc" || die "Download failed: $url.asc"
if ! verify_detached "$TB_FPR" "$KEY.part" "$OUT/$name.asc.part" "$OUT/$name.part"; then
    rm -f "$OUT/$name.part" "$OUT/$name.asc.part" "$KEY.part"
    die "The signature didn't check out, so the download was deleted."
fi
mv "$OUT/$name.part" "$OUT/$name"
mv "$OUT/$name.asc.part" "$OUT/$name.asc"
mv "$KEY.part" "$KEY"
# Keep only the newest copy
for f in "$OUT"/tor-browser-linux-*.tar.xz; do
    [ "$f" = "$OUT/$name" ] || rm -f "$f" "$f.asc"
done
note "Saved and verified: $OUT/$name"
note "extras/tor-browser.sh installs this copy instead of downloading one."
