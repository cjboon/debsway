#!/bin/bash
# KeePassXC, a password manager that keeps everything in one encrypted
# file you control. From Debian; qtwayland5 lets it run on Wayland
# without XWayland.
# Usage: bash keepassxc.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge keepassxc-minimal keepassxc
    note "Your password databases (.kdbx files) are left where they are."
    exit
fi

say "Installing KeePassXC"
apt_install keepassxc-minimal qtwayland5
note "Run it with: keepassxc   (or Super+d)"
note "It can also generate two-factor login codes (TOTP) for your accounts."
