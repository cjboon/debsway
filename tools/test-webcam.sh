#!/bin/bash
# Checks the webcam switch (bin/debsway-camera, extras/webcam.sh) on a pretend
# /sys with a USB camera, a USB keyboard and a root hub, and the menu's Webcam
# line through bin/radios with a pretend helper and sudo. Nothing is run as
# root and nothing outside a temp folder changes. Run by test.sh, or:
#   bash tools/test-webcam.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
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
[ "$(id -u)" -ne 0 ] || { echo "  ok    skipped: run as root, the helper would use the real /sys"; exit 0; }

# A USB device's raw descriptors: device, configuration, then an interface of
# class CLASS (14 = video, 3 = keyboard)
U=$T/sys/bus/usb/devices
device() { # NAME CLASS
    mkdir -p "$U/$1"
    printf '%b' "\\x12\\x01\\x00\\x02\\xef\\x02\\x01\\x40\\x00\\x00\\x00\\x00\\x00\\x00\\x01\\x02\\x00\\x01" \
        "\\x09\\x02\\x00\\x00\\x02\\x01\\x00\\x80\\xfa" "\\x08\\x0b\\x00\\x02\\x0e\\x03\\x00\\x00" \
        "\\x09\\x04\\x00\\x00\\x01\\x$(printf '%02x' "$2")\\x01\\x00\\x00" >"$U/$1/descriptors"
    echo 1 >"$U/$1/authorized"
}
device 1-6 14
device 1-7 3
mkdir -p "$U/usb1"; echo 1 >"$U/usb1/authorized"
cam() { DEBSWAY_SYS=$T/sys bash "$HERE/bin/debsway-camera" "$@"; }

check "a USB camera is found, and is on" test "$(cam status)" = on
cam off
check "off disconnects the camera's USB device" test "$(cat "$U/1-6/authorized")" = 0
check "...and nothing else (the keyboard stays)" test "$(cat "$U/1-7/authorized")" = 1
check "...the root hub too" test "$(cat "$U/usb1/authorized")" = 1
check "a disconnected camera is still found, as off" test "$(cam status)" = off
cam on
check "on connects it again" test "$(cat "$U/1-6/authorized")" = 1
cam added 1-6
check "udev's 'added' switches a new camera off" test "$(cat "$U/1-6/authorized")" = 0
cam added 1-7
check "...but not a keyboard" test "$(cat "$U/1-7/authorized")" = 1
cam added usb1 && cam added ../../x
check "...and a root hub or a strange name is quietly left alone" test $? -eq 0
check "...and touches nothing for them" test "$(cat "$U/usb1/authorized")" = 1
check "only on, off, status and added are accepted" not cam reboot
printf '\x12\x01' >"$U/1-7/descriptors"
check "short or broken descriptors are no camera" test "$(cam status)" = off
rm -rf "${U:?}/1-6"
check "with no camera: none" test "$(cam status)" = none
check "...and off says there is none" not cam off

# The menu's Webcam line: radios with a pretend helper and sudo
mkdir -p "$T/fake"
printf '#!/bin/sh\ncase $1 in status) cat "%s/state" ;; on|off) echo "$1" >"%s/state" ;; esac\n' "$T" "$T" >"$T/fake/helper"
printf '#!/bin/sh\necho "sudo $*" >>"%s/calls"\n[ "$1" != -n ] || shift\nexec "$@"\n' "$T" >"$T/fake/sudo"
chmod +x "$T/fake/"*
r() { PATH="$T/fake:$PATH" DEBSWAY_CAMERA="$T/fake/helper" DEBSWAY_SYS="$T/nosys" bash "$HERE/bin/radios" "$@"; }
echo off >"$T/state"
check "the menu lists the webcam with its state" grep -qx 'camera off' <<<"$(r list)"
r camera toggle
check "switching it goes through sudo, with on or off only" grep -qx "sudo -n $T/fake/helper on" "$T/calls"
check "...and switches it" test "$(r camera status)" = on
echo none >"$T/state"
check "with no camera the menu has no Webcam line" not grep -q camera <<<"$(r list)"
check "the menu calls it Webcam" grep -q 'camera) name=Webcam' "$HERE/bin/debsway-menu"

# The pieces the extra installs
check "udev runs it only for a whole USB device being added (not when switched on)" \
    grep -q 'ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", RUN+="/usr/local/libexec/debsway-camera added %k"' "$HERE/data/webcam-off.rules"
check "the sudo rule allows exactly on and off" grep -q 'NOPASSWD: %s on, %s off' "$HERE/extras/webcam.sh"

[ "$fails" -eq 0 ]
