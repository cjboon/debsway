#!/bin/bash
# Bluetooth, for headphones, keyboards, mice and a phone's connection. Installs
# bluez (bluetoothctl pairs devices in a terminal) and, if sound is set up, the
# part of PipeWire that plays sound over Bluetooth. The adapter starts switched
# OFF at every boot: switch it on from the debsway menu (Bluetooth) or with
# debsway --bluetooth on, and off again when you are done, so no radio is
# listening when you are not using it.
# Pair a device: debsway --bluetooth on, then  bluetoothctl  and type:
#   scan on          (wait until the device shows up)
#   pair AA:BB:...   trust AA:BB:...   connect AA:BB:...
# Usage: bash bluetooth.sh [--remove]
# summary: Bluetooth (off at start; switch it from the menu)
# status: apt:bluez
# files: bin/radios
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/bluetooth/main.conf

if [ "${1:-}" = --remove ]; then
    if [ -f "$CONF" ]; then
        tmp=$(mktemp)
        cp "$CONF" "$tmp"
        set_bluetooth_autoenable "$tmp" true
        sudo install -m 0644 "$tmp" "$CONF"
        rm -f "$tmp"
    fi
    apt_purge bluez libspa-0.2-bluetooth
    exit
fi

has_bluetooth || warn "No Bluetooth adapter found on this computer; installing it anyway (a USB adapter works once plugged in)."
say "Installing bluez"
apt_install bluez
# Sound over Bluetooth needs PipeWire's Bluetooth module; only if sound is set up
if is_installed pipewire-audio; then apt_install libspa-0.2-bluetooth; fi
install_bin radios

# Off at start. Edited on a copy so a half-written file is never left in /etc.
tmp=$(mktemp)
cat "$CONF" >"$tmp" 2>/dev/null || : >"$tmp"
set_bluetooth_autoenable "$tmp" false
sudo install -m 0644 "$tmp" "$CONF"
rm -f "$tmp"
sudo systemctl enable --now bluetooth.service >/dev/null 2>&1 || warn "Couldn't start the Bluetooth service now."
# Off now too, not only after the next boot
"$HOME/.local/bin/radios" bluetooth off >/dev/null 2>&1 || true
note "Bluetooth is off. Switch it on: debsway menu > Bluetooth, or  debsway --bluetooth on"
note "Pair a device with  bluetoothctl  (scan on, pair, trust, connect)."
