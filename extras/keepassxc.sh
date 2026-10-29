#!/bin/bash
# KeePassXC, a password manager that keeps everything in one encrypted
# file you control. It is the minimal build (keepassxc-minimal): no browser
# integration, no KeePassXC-Browser add-on for Firefox. Copy and paste a
# password or use auto-type instead; that keeps a web page, and the sandboxed
# Firefox, from having any way to talk to the password manager.
# qtwayland5 lets it run on Wayland without XWayland. Running this on a
# computer that has the full build (keepassxc-full, with webext-keepassxc-browser)
# switches it to the minimal one.
# Usage: bash keepassxc.sh [--remove]
# summary: KeePassXC password manager (no browser add-on)
# status: apt:keepassxc-full apt:keepassxc-minimal apt:keepassxc
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge keepassxc-full keepassxc-minimal keepassxc webext-keepassxc-browser
    note "Your password databases (.kdbx files) are left where they are."
    exit
fi

say "KeePassXC"
# The builds conflict: apt swaps one for the other. The add-on goes with the full build.
apt_drop keepassxc-full keepassxc webext-keepassxc-browser
if is_installed keepassxc-full || is_installed webext-keepassxc-browser; then
    note "Replacing keepassxc-full and the Firefox add-on with keepassxc-minimal (no browser integration)."
fi
apt_install keepassxc-minimal qtwayland5
note "Run it with: keepassxc   (or Super+d)"
note "It can also generate two-factor login codes (TOTP) for your accounts."
note "To use a password on a web page: copy it from KeePassXC (Ctrl+C) and paste it."
