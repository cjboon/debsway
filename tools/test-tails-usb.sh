#!/bin/bash
# Checks extras/tails-usb.sh's pieces (lib/tails.sh) without a network, sudo or
# a USB stick: reading Tails' release file, which disks may be offered (with a
# pretend lsblk), and writing with a read-back check onto a plain file. The
# signature checks it uses are tested in test-signatures.sh. Changes nothing
# outside a temp folder. Run by test.sh, or:  bash tools/test-tails-usb.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh"
. "$HERE/lib/appimage.sh"
. "$HERE/lib/tails.sh"
set +e +o pipefail

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
warn() { :; }

# ---- Tails' release file ----
release() { # VERSION URL SHA256 SIZE: a release file like Tails' latest.json
    cat <<EOF
{"build_target": "amd64", "channel": "stable", "product-name": "Tails",
 "installations": [{"version": "$1", "installation-paths": [
   {"type": "img", "target-files": [{"url": "$2", "sha256": "$3", "size": $4}]},
   {"type": "iso", "target-files": [{"url": "https://download.tails.net/x.iso", "sha256": "$3", "size": $4}]}]}]}
EOF
}
SHA=32eba91c65cd184206eb7c8e9b504277442cf17aae7816815a1d9401e9736761
URL=https://download.tails.net/tails/stable/tails-amd64-7.15.1/tails-amd64-7.15.1.img
release 7.15.1 "$URL" "$SHA" 1889533952 >"$T/latest.json"
check "the release file gives the version, the image, its SHA-256 and size" \
    test "$(tails_latest "$T/latest.json")" = "7.15.1 $URL $SHA 1889533952"
release 7.15.1 https://evil.example/tails.img "$SHA" 1889533952 >"$T/bad1.json"
check "an image anywhere but download.tails.net is refused" not tails_latest "$T/bad1.json"
release 7.15.1 "${URL/7.15.1.img/7.10.img}" "$SHA" 1889533952 >"$T/bad2.json"
check "an image whose name isn't the version's is refused" not tails_latest "$T/bad2.json"
release '7.15.1;rm' "$URL" "$SHA" 1889533952 >"$T/bad3.json"
check "a version that isn't a version is refused" not tails_latest "$T/bad3.json"
release 7.15.1 "$URL" nothex 1889533952 >"$T/bad4.json"
check "a checksum that isn't one is refused" not tails_latest "$T/bad4.json"
release 7.15.1 "$URL" "$SHA" 1000 >"$T/bad5.json"
check "a size no Tails image has is refused" not tails_latest "$T/bad5.json"
echo 'not json' >"$T/bad6.json"
check "a broken release file is refused" not tails_latest "$T/bad6.json"

# ---- which disks are offered ----
mkdir -p "$T/fake"
# the system runs from nvme0n1 (through LVM); sdb and sdd are USB sticks; sdc is
# a USB disk with /home on it; sda is a SATA disk
cat >"$T/fake/lsblk" <<'EOF'
#!/bin/sh
case "$*" in
    *"-dbn -o NAME,TRAN,TYPE,SIZE,MODEL"*)
        printf '%s\n' "nvme0n1 nvme disk 512110190592 Samsung SSD 980" "sda sata disk 1000204886016 WDC WD10" \
            "sdb usb disk 16008609792 SanDisk Ultra" "sdc usb disk 1000204886016 Seagate Expansion" \
            "sdd usb disk 7994343424 Kingston DataTraveler" "sr0 usb rom 1073741312 DVD" ;;
    *"-lno NAME -s"*) printf '%s\n' "vg-root" "nvme0n1p3_crypt" "nvme0n1p3" "nvme0n1" ;;
    *"MOUNTPOINTS /dev/sdc"*) printf '%s\n' "" "/home" ;;
    *"MOUNTPOINTS /dev/sdb"*) printf '%s\n' "" "/media/me/STICK" ;;
    *MOUNTPOINTS*) echo "" ;;
esac
EOF
printf '#!/bin/sh\necho /dev/mapper/vg-root\n' >"$T/fake/findmnt"
chmod +x "$T/fake/"*
disks=$(PATH="$T/fake:$PATH" usb_disks)
check "a USB stick is offered, with its size and model" grep -qx 'sdb 16008609792 SanDisk Ultra' <<<"$disks"
check "...even with a partition mounted by USB automount (it is unmounted first)" grep -q '^sdb ' <<<"$disks"
check "...and a small one is listed (the size is refused later)" grep -q '^sdd ' <<<"$disks"
check "the disk this system runs from is never offered" not grep -q '^nvme0n1 ' <<<"$disks"
check "a SATA disk is never offered" not grep -q '^sda ' <<<"$disks"
check "a USB disk holding /home is never offered" not grep -q '^sdc ' <<<"$disks"
check "a USB DVD drive is not a disk" not grep -q '^sr0 ' <<<"$disks"
# a system that runs from a USB disk: that one is never offered
sed -i 's/"nvme0n1p3" "nvme0n1"/"sdb1" "sdb"/' "$T/fake/lsblk"
check "a USB disk the system runs from is never offered" not grep -q '^sdb ' <<<"$(PATH="$T/fake:$PATH" usb_disks)"

# ---- writing, and reading it back ----
head -c 3000000 /dev/urandom >"$T/tails.img"
: >"$T/stick"
SUDO='' write_and_check "$T/tails.img" "$T/stick" >/dev/null 2>&1
check "the image is written to the stick" cmp -s "$T/tails.img" "$T/stick"
# a stick that loses what is written to it: a pretend dd that writes something else
printf '#!/bin/sh\nfor a; do case $a in of=*) head -c 3000000 /dev/zero >"${a#of=}" ;; esac; done\n' >"$T/fake/dd"
chmod +x "$T/fake/dd"
: >"$T/stick2"
check "a write that didn't land is caught by reading it back" \
    not env PATH="$T/fake:$PATH" bash -c '. "$1/lib.sh"; set +e; . "$1/lib/tails.sh"; PATH="$4:$PATH"; SUDO=; write_and_check "$2" "$3"' _ "$HERE" "$T/tails.img" "$T/stick2" "$T/fake"

# ---- the extra ----
E=$HERE/extras/tails-usb.sh
check "the stick is chosen by typing its name" grep -q 'Type its name, $name, to go on' "$E"
check "a stick under 8 GB is refused" grep -q 'MIN_STICK=$((7500 \* 1000 \* 1000))' "$E"
check "a download that fails the checks is deleted" grep -q 'rm -f "$img.part" "$sig"' "$E"
check "the Tails key is pinned" bash -c '. "$1/pins.sh"; [ "$TAILS_FPR" = A490D0F4D311A4153E2BB7CADBB802B258ACD84F ]' _ "$HERE"

[ "$fails" -eq 0 ]
