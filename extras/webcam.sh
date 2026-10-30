#!/bin/bash
# A webcam switch. A USB camera (most laptops' built-in ones, and plugged-in
# ones) starts switched OFF at every boot and whenever one is plugged in, and
# the debsway menu gets a Webcam line to switch it on and off (also:
# debsway --camera on|off). Off means its USB device is disconnected, as if
# it were unplugged, so no program can open it at all.
#  - bin/debsway-camera does it, as root (it writes the kernel's "authorized"
#    switch of the camera's USB device). Your user may run it with "on" or
#    "off" and nothing else (a rule in /etc/sudoers.d), so the menu needs no
#    password.
#  - A udev rule switches each camera off as it appears (data/webcam-off.rules).
#  - A camera that isn't on USB (some new laptops' MIPI cameras) isn't seen.
#  - A webcam often holds a microphone too: switched off, that goes as well.
# Like the microphone switch, a program running as you could switch it on the
# same way; a cover over the lens is the stronger kind. See THREAT-MODEL.md.
# Usage: bash webcam.sh [--remove]
# summary: Webcam off at start; switch it from the menu
# status: file:/usr/local/libexec/debsway-camera
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

HELPER=/usr/local/libexec/debsway-camera
RULE=/etc/udev/rules.d/90-debsway-webcam.rules
SUDOERS=/etc/sudoers.d/debsway-camera

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$RULE"
    sudo udevadm control --reload-rules 2>/dev/null || true
    # on again, as it was before
    if [ -x "$HELPER" ]; then sudo "$HELPER" on >/dev/null 2>&1 || true; fi
    sudo rm -f "$SUDOERS" "$HELPER"
    sudo rmdir /usr/local/libexec 2>/dev/null || true
    note "The webcam is on again and stays as the system leaves it."
    exit
fi

say "The webcam switch"
sudo install -d -o root -g root -m 0755 /usr/local/libexec
sudo install -o root -g root -m 0755 "$DEBSWAY_DIR/bin/debsway-camera" "$HELPER"
# the menu's Webcam line goes through radios
install_bin radios

rule=$(mktemp)
printf '# Written by debsway extras/webcam.sh. %s may switch the webcam on and off,\n# and nothing else, as root.\n%s ALL=(root) NOPASSWD: %s on, %s off\n' \
    "$(id -un)" "$(id -un)" "$HELPER" "$HELPER" >"$rule"
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so it wasn't installed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"

say "Off at every boot, and when one is plugged in"
sudo install -o root -g root -m 0644 "$DEBSWAY_DIR/data/webcam-off.rules" "$RULE"
sudo udevadm control --reload-rules 2>/dev/null || warn "Couldn't reload udev's rules; they apply from the next boot."

case $("$HELPER" status) in
    none)
        note "No USB camera found now. A camera plugged in later starts off too."
        note "(A built-in camera that isn't on USB, as in some new laptops, isn't seen.)" ;;
    *)
        sudo "$HELPER" off >/dev/null && note "The webcam is off now." ;;
esac
note "Switch it from the debsway menu (Webcam), or: debsway --camera on   (and off)"
note "A cover over the lens is still the stronger kind: a program running as you could switch it on."
