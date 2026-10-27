#!/bin/bash
# Electrum (Bitcoin wallet) from Debian's own packages, which Debian
# keeps patched. It uses Qt5, which runs on Wayland via qtwayland5 (base).
# Usage: bash electrum.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge electrum python3-electrum
    note "Your wallets are kept in ~/.electrum. Back them up before deleting anything."
    exit
fi

say "Installing electrum"
apt_install electrum qtwayland5
note "Run it with: electrum   (or Super+d). Wallets live in ~/.electrum."
