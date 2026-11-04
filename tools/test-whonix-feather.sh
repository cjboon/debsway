#!/bin/bash
# Checks what extras/whonix.sh writes into the Workstation before its first
# boot: image_put on a small real disk image (made with sfdisk, mke2fs and
# qemu-img; written with debugfs, as on a real install), executables 0755 with
# --exec and the rest 0644, owned by root; and the Feather download, with a
# pretend wget and signature check: Feather's Tails/Whonix build, only from the
# signed hash list, and a failure that warns instead of stopping the install.
# Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-whonix-feather.sh
# shellcheck disable=SC2016  # the inner shells and pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
export PATH=/usr/sbin:/sbin:$PATH
# The two functions, taken from the script itself
fn() { awk -v f="$1() {" '$0 == f { p = 1 } p { print } p && /^}$/ { exit }' "$HERE/extras/whonix.sh"; }
eval "$(fn image_put)"
eval "$(fn workstation_feather)"
die() { echo "die: $*" >&2; exit 1; }
warn() { echo "warn: $*" >&2; }
note() { :; }

if command -v debugfs >/dev/null && command -v qemu-img >/dev/null && command -v mke2fs >/dev/null; then
    raw=$T/disk.raw
    truncate -s 64M "$raw"
    printf 'label: gpt\nstart=2048, name="primary"\n' | sfdisk -q "$raw" >/dev/null 2>&1
    mke2fs -q -F -t ext4 -E offset=$((2048 * 512)) "$raw" 60M >/dev/null 2>&1
    fs="$raw?offset=$((2048 * 512))"
    printf 'mkdir usr\nmkdir usr/local\nmkdir usr/local/lib\nmkdir usr/local/bin\nmkdir usr/local/share\n' |
        debugfs -w -f - "$fs" >/dev/null 2>&1
    qemu-img convert -O qcow2 "$raw" "$T/ws.qcow2" && rm -f "$raw"
    printf 'the program\n' >"$T/prog"
    printf 'a menu entry\n' >"$T/entry"
    ( image_put "$T/ws.qcow2" --exec "$T/prog" /usr/local/lib/feather/feather.AppImage \
        "$T/entry" /usr/local/share/applications/feather.desktop ) 2>"$T/err"
    check "image_put writes into a real disk image (and it still checks out)" test ! -s "$T/err"
    qemu-img convert -O raw "$T/ws.qcow2" "$raw"
    st() { debugfs -R "stat $1" "$fs" 2>/dev/null; }
    check "...--exec: 0755, owned by root, in a folder it made" bash -c '
        grep -q "Mode: *0755" <<<"$1" && grep -q "User: *0 *Group: *0" <<<"$1"' _ "$(st /usr/local/lib/feather/feather.AppImage)"
    check "...the rest 0644" grep -q 'Mode: *0644' <<<"$(st /usr/local/share/applications/feather.desktop)"
    check "...with their contents" test "$(debugfs -R 'cat /usr/local/lib/feather/feather.AppImage' "$fs" 2>/dev/null)" = "the program"
fi

# The Feather download
latest_github_tag() { echo "${FAKE_VERSION-2.9.1}"; }
wget() { # -q --show-progress -O FILE URL
    echo "$5" >>"$T/urls"
    printf 'from %s\n' "$5" >"$4"
}
verify_clearsigned() { [ -z "${FAKE_BADSIG:-}" ] && cp "$3" "$4"; }
check_sha256() { [ -z "${FAKE_BADSUM:-}" ]; }
apt_install() { :; }
W=$T/work
mkdir -p "$W"
( workstation_feather "$W" && echo "version $FEATHER_VERSION" ) >"$T/out" 2>&1
check "Feather's Tails/Whonix build (no Tor of its own) and its signed hash list" bash -c '
    grep -qx "https://featherwallet.org/files/releases/hashes-2.9.1.txt" "$1" &&
    grep -qx "https://featherwallet.org/files/releases/linux-appimage-a/feather-2.9.1-a.AppImage" "$1"' _ "$T/urls"
check "...ready to put in the Workstation" bash -c 'grep -q "linux-appimage-a" "$1/feather.AppImage" && grep -qx "version 2.9.1" "$2"' _ "$W" "$T/out"
check "...with Feather's pinned key" grep -q 'verify_clearsigned "$FEATHER_FPR" "$FEATHER_KEY_URL"' "$HERE/extras/whonix.sh"
rm -f "$W/feather.AppImage"
for bad in FAKE_BADSIG FAKE_BADSUM; do
    if (export "$bad=1"; workstation_feather "$W") >/dev/null 2>&1 || [ -e "$W/feather.AppImage" ]; then
        printf '  FAIL  %s\n' "a bad signature or checksum ($bad): no Feather"; fails=$((fails + 1))
    else
        printf '  ok    %s\n' "a bad signature or checksum ($bad): no Feather, and the install goes on (a warning, not a stop)"
    fi
done
check "a version that doesn't look like one: nothing is downloaded" bash -c '
    : >"$1/urls"; (FAKE_VERSION="2.9.1/../x"; workstation_feather "$1/work"); [ $? -ne 0 ] && [ ! -s "$1/urls" ]' _ "$T"
check "the launcher runs it without FUSE" grep -qx 'APPIMAGE_EXTRACT_AND_RUN=1 exec /usr/local/lib/feather/feather.AppImage "$@"' "$HERE/data/whonix-feather"
check "...and the install puts both, executable, and the menu entry in the Workstation" bash -c '
    grep -qF -- "--exec \"\$work/feather.AppImage\" /usr/local/lib/feather/feather.AppImage" "$1" &&
    grep -qF -- "--exec \"\$WREN_DIR/data/whonix-feather\" /usr/local/bin/feather" "$1" &&
    grep -qF "/usr/local/share/applications/feather.desktop" "$1"' _ "$HERE/extras/whonix.sh"

[ "$fails" -eq 0 ]
