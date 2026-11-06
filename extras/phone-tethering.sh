#!/bin/bash
# For an iPhone: a phone's mobile data on this computer, through the USB cable. An
# Android phone needs nothing from this: plug it in and turn on "USB
# tethering" in its settings. An iPhone also needs usbmuxd and the pairing
# tools this installs: plug it in, tap Trust on the phone, turn on Personal
# Hotspot. Then the tether command (parts/tether.sh, in the base) connects it,
# asking first. (A phone's Wi-Fi hotspot is just a Wi-Fi network: pick it in nmtui,
# nothing to install.) To use only the phone,
# switch Wi-Fi off first: Wren menu > Wi-Fi, or  wrenctl --wifi off
# Usage: bash phone-tethering.sh [--remove | --manual]
# summary: Phone tethering over USB (iPhone and Android)
# security: some
# status: apt:usbmuxd
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge usbmuxd libimobiledevice-utils
    exit
fi

say "Installing the phone tethering tools"
apt_install usbmuxd libimobiledevice-utils
cat <<'TEXT'

    Android: plug the phone in, then Settings > Network > Hotspot & tethering >
             USB tethering.
    iPhone:  plug it in, tap Trust on the phone, then Settings > Personal Hotspot.
             If the computer does not see it: idevicepair pair
    Then a window asks whether to connect, while you are offline, or type: tether
    To use only the phone's data, switch Wi-Fi off:  wrenctl --wifi off
TEXT
