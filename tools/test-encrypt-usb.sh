#!/bin/bash
# Checks encrypt-usb.sh with a pretend sudo that only writes down what it is asked,
# and a pretend lsblk and findmnt: only USB sticks are offered, nothing is erased
# until you type the stick's name, and the steps run in order on that stick. No
# disk is touched. Run by test.sh, or:  bash tools/test-encrypt-usb.sh
# shellcheck disable=SC2016  # the pretend programs expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# A copy of Wren Linux whose lib.sh keeps the test's PATH, so the pretend programs are found
R=$T/r
mkdir -p "$R" "$T/bin" "$T/home"
sed 's|^export PATH=.*|export PATH="$EU_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q EU_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
for f in packages.sh pins.sh lib data docs bin encrypt-usb.sh; do ln -s "$HERE/$f" "$R/$f"; done
# sudo: writes it all down, runs nothing; fails for a word in $T/fail-on
cat >"$T/bin/sudo" <<EOF
#!/bin/sh
[ "\$1" = -v ] && exit 0
echo "\$*" >>"$T/calls"
cat >/dev/null <&0 2>/dev/null &
if [ -e "$T/fail-on" ]; then case "\$*" in *"\$(cat "$T/fail-on")"*) exit 1 ;; esac; fi
exit 0
EOF
# the system runs from nvme0n1; sdb and sdd are USB sticks; sda a SATA disk
cat >"$T/bin/lsblk" <<EOF
#!/bin/sh
case "\$*" in
    *"-dbn -o NAME,TRAN,TYPE,SIZE,MODEL"*) cat "$T/disks" ;;
    *"-lno NAME -s"*) printf '%s\n' vg-root nvme0n1p3_crypt nvme0n1p3 nvme0n1 ;;
    *"-lno MOUNTPOINTS"*) cat "$T/mounts" 2>/dev/null ;;
    *"-lnpo NAME,TYPE"*) printf '%s\n' "\${3:-/dev/x} disk" "\${3:-/dev/x}1 part" ;;
    *"-ln -o TYPE"*) cat "$T/types" 2>/dev/null ;;
esac
EOF
printf '#!/bin/sh\necho /dev/mapper/vg-root\n' >"$T/bin/findmnt"
printf '#!/bin/sh\ncase "$*" in *Status*) echo "install ok installed" ;; *Depends*) echo "cryptsetup, e2fsprogs, fdisk, util-linux" ;; esac\n' >"$T/bin/dpkg-query"
for c in cryptsetup mkfs.ext4 sfdisk wipefs; do printf '#!/bin/sh\nexit 0\n' >"$T/bin/$c"; done
chmod +x "$T/bin/"*
export EU_TEST_PATH="$T/bin:$PATH" HOME=$T/home WREN_SUDO=$T/bin/sudo
[ "$(bash -c '. "$1/lib.sh"; command -v sudo' _ "$R")" = "$T/bin/sudo" ] || { echo "  FAIL  the real sudo would run; stopping"; exit 1; }

ONE='sdb usb disk 16008609792 SanDisk Ultra'
TWO='sdd usb disk 7994343424 Kingston'
OTHERS='nvme0n1 nvme disk 512110190592 Samsung
sda sata disk 1000204886016 WDC'
run() { # ANSWER... (then EU_ARGS): the script, these typed answers
    : >"$T/calls"
    printf '%s\n' "$@" >"$T/answers"
    # shellcheck disable=SC2086  # EU_ARGS: none, or one word
    WREN_TEST_ANSWERS=$T/answers bash "$R/encrypt-usb.sh" ${EU_ARGS:-} >"$T/out" 2>&1
}
touched() { [ -s "$T/calls" ]; }

printf '%s\n' "$OTHERS" >"$T/disks"
check "no USB stick: it says so" not run sda
check "...offers no other disk, and touches nothing" bash -c 'grep -q "No USB stick found" "$1" && [ ! -s "$2" ]' _ "$T/out" "$T/calls"

printf '%s\n' "$OTHERS" "$ONE" >"$T/disks"
run sdc
check "a stick: the name mistyped: nothing is changed" bash -c 'grep -q "Nothing was changed" "$1" && [ ! -s "$2" ]' _ "$T/out" "$T/calls"
check "...it shows the stick, and says all of it goes" bash -c 'grep -q "sdb  16008 MB  SanDisk Ultra" "$1" && grep -q "EVERYTHING on sdb" "$1"' _ "$T/out"
check "...and offers no other disk" not grep -qE 'sda|nvme0n1' "$T/out"
run ''
check "Enter alone: nothing is changed" not touched
run sdb 'bad name;x'
check "a stick's name that isn't one: nothing is changed" not touched
printf 'crypt\n' >"$T/types"
run sdb ''
check "a stick that is unlocked and in use: refused" bash -c 'grep -q "Lock it first" "$1" && [ ! -s "$2" ]' _ "$T/out" "$T/calls"
rm "$T/types"

printf '/media/me/OLD\n' >"$T/mounts"
run sdb ''
check "its name typed: it goes through" grep -q 'Done: sdb is encrypted and locked' "$T/out"
check "...the steps, on that stick, in order" python3 -I -c '
import re, sys
c = open(sys.argv[1]).read().split("\n")
want = ["umount /media/me/OLD", "wipefs -a /dev/sdb", "sfdisk --quiet /dev/sdb", "cryptsetup luksFormat -q --type luks2 --verify-passphrase /dev/sdb1",
        "cryptsetup open /dev/sdb1 wren-usb-", "mkfs.ext4 -q -L WREN-USB /dev/mapper/wren-usb-", "mount /dev/mapper/wren-usb-", "chown ", "chmod 700 ", "cryptsetup close wren-usb-"]
at = 0
for w in want:
    while at < len(c) and not c[at].startswith(w):
        at += 1
    assert at < len(c), w
    at += 1
' "$T/calls"
check "...nothing on any other disk" not grep -qE '/dev/(sda|sdd|nvme)' "$T/calls"
check "...and it says how to open and lock it" bash -c 'grep -q "usb mount sdb1" "$1" && grep -q "usb unmount sdb1" "$1"' _ "$T/out"
rm "$T/mounts"
run sdb MYKEYS
check "a name of your own for it" grep -q 'mkfs.ext4 -q -L MYKEYS ' "$T/calls"

echo 'cryptsetup open' >"$T/fail-on"
check "a passphrase that doesn't open it: it stops" not run sdb ''
check "...before any file system is made" not grep -q mkfs "$T/calls"
echo mkfs >"$T/fail-on"
run sdb ''
check "a step that fails after it opened: the stick is closed again" grep -q '^cryptsetup close wren-usb-' "$T/calls"
rm "$T/fail-on"

printf '%s\n' "$ONE" "$TWO" >"$T/disks"
run 2 sdd ''
check "two sticks: it asks which, by number" grep -q '^wipefs -a /dev/sdd$' "$T/calls"
run 9
check "...a number that isn't one: nothing is changed" not touched
EU_ARGS=sdb run sdb ''
check "a name on the command line: that one" grep -q '^wipefs -a /dev/sdb$' "$T/calls"
EU_ARGS=sda run sda ''
check "...one that isn't a USB stick: refused" bash -c 'grep -q "sda isn.t one of these" "$1" && [ ! -s "$2" ]' _ "$T/out" "$T/calls"
EU_ARGS=--nonsense run
check "an option it doesn't know: nothing is changed" not touched

[ "$fails" -eq 0 ]
