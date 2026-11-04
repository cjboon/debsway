#!/bin/bash
# Hardware wallets over USB (Trezor, Ledger, Coldcard, BitBox02, KeepKey), for
# Sparrow and Electrum (Bitcoin) and Feather (Monero): the coins' keys stay on
# the device, which shows what you are about to sign on its own screen, so a
# hacked computer can't spend them, or quietly change where they go.
#  - A udev rule (data/hardware-wallets.rules) gives these devices to you, at
#    the keyboard, and to no one else: no group, no other user, none of Wren
#    Linux's sandboxes (uaccess). (extras/wallet-sandbox.sh can add one wallet's
#    user, if you choose that.)
#  - No maker's app is installed: Sparrow, Electrum and Feather talk to the
#    devices themselves (wrenctl install sparrow-wallet, electrum, feather-wallet).
#  - Safer still: a device that never connects at all. Coldcard, Jade,
#    Keystone and SeedSigner sign from a QR code or a microSD card; Sparrow
#    does both (the webcam extra for QR codes, usb mount for a card). Blockstream
#    Jade over USB is a serial port, not covered here: use its QR mode.
# Usage: bash hardware-wallet.sh [--remove | --manual]
# summary: Hardware wallets over USB (Trezor, Ledger...)
# security: most
# files: data/hardware-wallets.rules
# status: file:/etc/udev/rules.d/60-wren-hardware-wallets.rules
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

# (a test puts it in a folder of its own)
RULE=${WREN_HW_ROOT:-}/etc/udev/rules.d/60-wren-hardware-wallets.rules

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$RULE"
    sudo udevadm control --reload-rules 2>/dev/null || true
    note "Hardware wallets are as Debian leaves them again (most need the rule to be reached)."
    exit
fi

say "Hardware wallets"
sudo install -D -o root -g root -m 0644 "$WREN_DIR/data/hardware-wallets.rules" "$RULE"
sudo udevadm control --reload-rules 2>/dev/null || warn "Couldn't reload udev's rules; they apply from the next boot."
sudo udevadm trigger --subsystem-match=usb --subsystem-match=hidraw --action=change 2>/dev/null || true
note "Trezor, Ledger, Coldcard, BitBox02 and KeepKey are yours to use, at the keyboard only."
note "Plug it in (again), then open Sparrow, Electrum or Feather and connect it from there."
missing=''
for c in sparrow electrum feather; do command -v "$c" >/dev/null || [ -x "$BIN/$c" ] || missing+=" $c"; done
[ -z "$missing" ] || note "Not installed here:$missing (wrenctl install sparrow-wallet, electrum, feather-wallet)."
echo
note "What matters most, whatever the device:"
note "  - Check the address and amount on the device's own screen, not the computer's."
note "  - The recovery words are the real key: on paper or metal, never typed into a"
note "    computer or photographed."
note "  - Buy it from the maker itself, and check it is genuine the way the maker says."
note "  - Safest: a device that never connects (Coldcard, Jade, Keystone, SeedSigner),"
note "    signing from a QR code or a microSD card in Sparrow."
