#!/bin/bash
# Use a phone's mobile data on this computer, through the USB cable. An Android
# phone needs nothing but NetworkManager: plug it in and turn on "USB
# tethering" in its settings. An iPhone also needs usbmuxd and the pairing
# tools this installs: plug it in, tap Trust on the phone, turn on Personal
# Hotspot. A new wired connection then appears. (A phone's Wi-Fi hotspot is just
# a Wi-Fi network: pick it in nmtui, nothing to install.) To use only the phone,
# switch Wi-Fi off first: debsway menu > Wi-Fi, or  debsway --wifi off
# Usage: bash phone-tethering.sh [--remove]
# summary: Phone tethering over USB (iPhone and Android)
# status: apt:usbmuxd
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge usbmuxd libimobiledevice-utils
    exit
fi

say "Installing the phone tethering tools"
apt_install usbmuxd libimobiledevice-utils
is_installed network-manager ||
    warn "NetworkManager isn't installed, and it is what brings the phone's connection up: bash $DEBSWAY_DIR/parts/network-manager.sh"
cat <<'TEXT'

    Android: plug the phone in, then Settings > Network > Hotspot & tethering >
             USB tethering.
    iPhone:  plug it in, tap Trust on the phone, then Settings > Personal Hotspot.
             If the computer does not see it: idevicepair pair
    Then a new wired connection appears (nmtui shows it). To use only the
    phone's data, switch Wi-Fi off:  debsway --wifi off
TEXT
