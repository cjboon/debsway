# shellcheck shell=bash
# lib/tails.sh: getting Tails onto a USB stick (extras/tails-usb.sh). Sourced
# after lib.sh and lib/appimage.sh (its signature checks). The signing key is
# pinned in pins.sh (TAILS_FPR); a copy is only used if it is that key.
#
# A download is used only if both hold:
#  - its OpenPGP signature is good and made by the Tails signing key, and
#  - its SHA-256 and size are the ones in Tails' release file for the newest
#    version (fetched over HTTPS from tails.net). A signature alone would also
#    accept an older, genuinely signed Tails with known holes; the release
#    file ties the image to the current release.

TAILS_LATEST_URL=https://tails.net/install/v2/Tails/amd64/stable/latest.json
TAILS_SIG_BASE=https://tails.net/torrents/files
TAILS_OFFLINE=${OFFLINE_DIR:-$WREN_DIR/offline}/tails

# tails_latest JSON-FILE: "VERSION URL SHA256 SIZE" of the USB image (.img) in
# Tails' release file, or nothing (and status 1) if it isn't as expected
tails_latest() {
    python3 -I - "$1" <<'PY' 2>/dev/null
import json, re, sys
d = json.load(open(sys.argv[1]))
inst = d["installations"][0]
v = inst["version"]
f = [p for p in inst["installation-paths"] if p["type"] == "img"][0]["target-files"][0]
url, sha, size = f["url"], f["sha256"], int(f["size"])
assert re.fullmatch(r"[0-9]+(\.[0-9]+)+(~rc[0-9]+)?", v), v
assert url == "https://download.tails.net/tails/stable/tails-amd64-%s/tails-amd64-%s.img" % (v, v), url
assert re.fullmatch(r"[0-9a-f]{64}", sha), sha
assert 500 * 2**20 < size < 8 * 2**30, size
print(v, url, sha, size)
PY
}

# tails_image_ok IMG SIG KEY SHA256 SIZE: the signature is good and the
# Tails signing key's, and the file is exactly the one the release file names
tails_image_ok() {
    local img=$1 sig=$2 key=$3 sha=$4 size=$5
    [ -f "$img" ] && [ "$(stat -c %s "$img")" = "$size" ] || { warn "$img isn't the size Tails' release file says."; return 1; }
    verify_detached "$TAILS_FPR" "$key" "$sig" "$img" || { warn "The signature on $img isn't the Tails signing key's."; return 1; }
    echo "$sha  $img" | sha256sum -c --quiet - >/dev/null 2>&1 ||
        { warn "$img isn't the image Tails' release file names (an older one?)."; return 1; }
}
