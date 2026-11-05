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
T=$(mktemp -d) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }
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
    rm -f "$raw"
    # --edit: a file already in the image, changed with sed (the Gateway's DNS line)
    printf '## VirtualBox Clearnet DNS:\n#nameserver 10.0.2.3\n' >"$T/resolv"
    ( image_put "$T/ws.qcow2" "$T/resolv" /etc/resolv.conf.whonix ) 2>>"$T/err"
    ( image_put "$T/ws.qcow2" --edit /etc/resolv.conf.whonix 's/^#nameserver 10\.0\.2\.3$/nameserver 10.0.2.3/' ) 2>"$T/err"
    qemu-img convert -O raw "$T/ws.qcow2" "$raw"
    check "--edit changes a file already in the image, and only that line" test \
        "$(debugfs -R 'cat /etc/resolv.conf.whonix' "$fs" 2>/dev/null)" = "$(printf '## VirtualBox Clearnet DNS:\nnameserver 10.0.2.3')"
    rm -f "$raw"
    sum() { sha256sum "$T/ws.qcow2" | cut -d' ' -f1; }
    before=$(sum)
    out=$( ( image_put "$T/ws.qcow2" --edit /etc/not-there 's/a/b/' ) 2>&1)
    check "...a file that isn't there: it stops, and the image is unchanged" bash -c '
        grep -q "Couldn.t read /etc/not-there" <<<"$1" && [ "$2" = "$3" ]' _ "$out" "$before" "$(sum)"
    # A VM switched off without shutting down: its journal left for its next boot
    qemu-img convert -O raw "$T/ws.qcow2" "$raw"
    debugfs -w -R "feature needs_recovery" "$fs" >/dev/null 2>&1
    qemu-img convert -O qcow2 "$raw" "$T/dirty.qcow2" && rm -f "$raw"
    dirty() { sha256sum "$T/dirty.qcow2" | cut -d' ' -f1; }
    d0=$(dirty)
    out=$( ( image_put "$T/dirty.qcow2" "$T/prog" /usr/local/bin/x ) 2>&1)
    check "a disk switched off without shutting down (its journal to replay): not edited, and it says how to fix that" bash -c '
        grep -q "switched off without shutting down" <<<"$1" && grep -q "shut it down from inside" <<<"$1" &&
        [ "$2" = "$3" ] && [ ! -e "$4.raw" ]' _ "$out" "$d0" "$(dirty)" "$T/dirty.qcow2"
    # A disk with errors but no journal flag (switched off with orphaned files, as
    # a Gateway was on a real install): refused before it is edited, not after
    qemu-img convert -O raw "$T/ws.qcow2" "$raw"
    # (a file's link count wrong: e2fsck reports it, as it does what a switch-off leaves)
    debugfs -w -R "sif /etc/resolv.conf.whonix links_count 3" "$fs" >/dev/null 2>&1
    qemu-img convert -O qcow2 "$raw" "$T/broken.qcow2" && rm -f "$raw"
    b0=$(sha256sum "$T/broken.qcow2" | cut -d' ' -f1)
    out=$( ( image_put "$T/broken.qcow2" "$T/prog" /usr/local/bin/x ) 2>&1)
    check "...a disk whose file system doesn't check out: refused before editing, with how to put it right" bash -c '
        grep -q "switched off without shutting down" <<<"$1" && ! grep -q "after editing" <<<"$1" && [ "$2" = "$3" ]' \
        _ "$out" "$b0" "$(sha256sum "$T/broken.qcow2" | cut -d' ' -f1)"
    # A failed write back (a full disk): never in the image's place
    # shellcheck disable=SC2317,SC2329  # the stand-in is called by image_put
    out=$( ( qemu-img() { if [[ " $* " == *" -O qcow2 "* ]]; then echo "No space left on device" >&2; return 1; fi; command qemu-img "$@"; }
        image_put "$T/ws.qcow2" "$T/prog" /usr/local/bin/x ) 2>&1)
    check "writing the image back fails (a full disk): it stops, and the image is unchanged, nothing left beside it" bash -c '
        grep -q "It is unchanged" <<<"$1" && [ "$2" = "$3" ] && [ ! -e "$4.new" ] && [ ! -e "$4.raw" ]' _ "$out" "$before" "$(sum)" "$T/ws.qcow2"
    # shellcheck disable=SC2317,SC2329  # the stand-in is called by image_put
    out=$( ( df() { printf "Filesystem 1M-blocks Used Available Capacity Mounted\nx 100 99 1 99%% /\n"; }
        image_put "$T/ws.qcow2" "$T/prog" /usr/local/bin/x ) 2>&1)
    check "...too little room to begin with: it stops before touching anything" bash -c '
        grep -q "needs about .* MB free" <<<"$1" && [ "$2" = "$3" ] && [ ! -e "$4.raw" ]' _ "$out" "$before" "$(sum)" "$T/ws.qcow2"
fi

# The Feather download
latest_github_tag() { echo "${FAKE_VERSION-2.9.1}"; }
wget() { # -q --show-progress -O FILE URL
    echo "$5" >>"$T/urls"
    printf 'from %s\n' "$5" >"$4"
}
verify_clearsigned() { [ -z "${FAKE_BADSIG:-}" ] && cp "$3" "$4"; }
check_sha256() { [ -z "${FAKE_BADSUM:-}" ]; }
# shellcheck disable=SC2317,SC2329  # called by workstation_feather
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

# The Gateway's outside network card: libvirt's (whose passt can't be given
# options) taken out, Wren Linux's put in, on the main PCI bus (eth0), joined to
# the passt bin/whonix starts; the internal card to the Workstation kept
eval "$(fn gateway_net_xml)"
eval "$(sed -n '/^GW_NET_SOCK=/p; /^GW_NET_MAC=/p' "$HERE/extras/whonix.sh")"
cat >"$T/gw.xml" <<'EOF'
<domain type='kvm'>
  <name>Whonix-Gateway</name>
  <devices>
    <interface type='user'>
      <backend type='passt'/>
      <model type='virtio'/>
    </interface>

    <interface type="udp">
      <source address="127.0.0.1" port="5577"/>
    </interface>
  </devices>
</domain>
EOF
gateway_net_xml "$T/gw.xml" "$T/gw1.xml" 0x1e
gateway_net_xml "$T/gw1.xml" "$T/gw2.xml" 0x1e
check "the Gateway's file: libvirt's outside card gone, the internal one kept" bash -c '
    ! grep -q "<interface type=.user.>" "$1" && grep -q "<interface type=\"udp\">" "$1"' _ "$T/gw1.xml"
check "...Wren Linux's card in its place: on the main bus, slot 0x1e, joined to the passt socket" bash -c '
    grep -q "xmlns:qemu=" "$1" && grep -qF "\"bus\": \"pcie.0\", \"addr\": \"0x1e\"" "$1" &&
    grep -qF "\"path\": \"$2\"" "$1"' _ "$T/gw1.xml" "$GW_NET_SOCK"
check "...done twice: the same file (one card, not two)" cmp "$T/gw1.xml" "$T/gw2.xml"
check "...and libvirt can read it (xmllint finds it well formed)" bash -c '! command -v xmllint >/dev/null || xmllint --noout "$1"' _ "$T/gw1.xml"

# The Gateway's files for each bridge: its own DNS on only for those that look
# names up, Tor held off when a bridge is wanted but none was given
# webtunnel: lyrebird from the Tor Project's repository (its key pinned), copied
# in, and the version written in kept, for bin/whonix to compare
eval "$(fn lyrebird_record)"
eval "$(fn gateway_lyrebird | sed "s|\[ -x /usr/bin/lyrebird \]|[ -x \"\$T/lyrebird\" ]|")"
: >"$T/lyrebird"
chmod +x "$T/lyrebird"
eval "$(sed -n '/^LYREBIRD_COPY=/p' "$HERE/extras/whonix.sh")"
LYREBIRD_COPY=$T/lyrebird-version
add_torproject_repo() { echo add_torproject_repo >>"$T/lyr-calls"; }
# shellcheck disable=SC2317,SC2329  # called by gateway_lyrebird
apt_install() { echo "apt_install $*" >>"$T/lyr-calls"; }
dpkg-query() { echo 0.6.1-1; }
eval "$(fn gateway_config)"
eval "$(sed -n '/^bridge_needs_dns() /p' "$HERE/extras/whonix.sh")"
bridge_summary() { echo "$BRIDGE_TYPE"; }
tor_bridge_config() { echo "Bridge $BRIDGE_TYPE ..."; }
gc() { BRIDGE_TYPE=$1 BRIDGE_WANTED=$2; mkdir -p "$T/gc"; gateway_config "$T/gc"; printf '%s\n' "${GW_FILES[@]}"; }
for b in snowflake webtunnel; do
    check "$b: the Gateway's own DNS is turned on (10.0.2.3, where passt hands it on)" grep -qxF 's/^#nameserver 10\.0\.2\.3$/nameserver 10.0.2.3/' <<<"$(gc $b true)"
done
for b in obfs4 none; do
    check "$b: it stays off (and is turned off if it was on)" grep -qxF 's/^nameserver 10\.0\.2\.3$/#nameserver 10.0.2.3/' <<<"$(gc $b false)"
done
out=$(gc webtunnel true)
check "webtunnel: lyrebird from the Tor Project's pinned repository, before anything is written" \
    test "$(tail -n 2 "$T/lyr-calls" | paste -sd';')" = "add_torproject_repo;apt_install lyrebird"
check "...copied into the Gateway as /usr/bin/lyrebird, 0755" grep -qx -- '--exec' <<<"$(grep -B1 -x /usr/bin/lyrebird <<<"$out" | head -1)"
check "...its version not kept before the Gateway's files are written (a failed write leaves no false record)" test ! -e "$LYREBIRD_COPY"
BRIDGE_TYPE=webtunnel gateway_lyrebird
lyrebird_record
check "...and kept once they are" grep -qx '0.6.1-1' "$LYREBIRD_COPY"
: >"$T/lyr-calls"
gc snowflake true >/dev/null
lyrebird_record
check "another bridge chosen: nothing installed, and the kept version goes" bash -c '[ ! -s "$1" ] && [ ! -e "$2" ]' _ "$T/lyr-calls" "$LYREBIRD_COPY"

gc none true >/dev/null
check "a bridge wanted but none given: Tor held off" grep -qx 'DisableNetwork 1' "$T/gc/40_tor_control_panel.conf"
gc obfs4 true >/dev/null
check "...a bridge given: Tor on (a choice made again leaves nothing of the one before)" grep -qx 'DisableNetwork 0' "$T/gc/40_tor_control_panel.conf"

# The saved download, as the install looks for it: in strict mode (set -euo
# pipefail, as lib.sh runs every script), with none saved yet the install must
# go on to download it, not end there without a word
mkdir -p "$T/saved"
sa() { bash -c 'set -euo pipefail; SAVED=$1 EDITION=LXQt
    eval "$(sed -n "/^saved_archive() {/,/^}/p" "$2")"; a=$(saved_archive); echo "on:$a"' _ "$T/saved" "$HERE/extras/whonix.sh"; }
check "no Whonix saved yet: the install goes on (to download it)" test "$(sa)" = "on:"
: >"$T/saved/Whonix-LXQt-18.1.Intel_AMD64.qcow2.libvirt.xz"
: >"$T/saved/Whonix-LXQt-18.2.4.2.Intel_AMD64.qcow2.libvirt.xz"
check "...two saved: the newest is used" test "$(sa)" = "on:$T/saved/Whonix-LXQt-18.2.4.2.Intel_AMD64.qcow2.libvirt.xz"

[ "$fails" -eq 0 ]
