#!/bin/bash
# Command-line clipboard: wl-copy and wl-paste.
# Usage: bash wl-clipboard.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge wl-clipboard
    exit
fi

say "Installing wl-clipboard"
apt_install wl-clipboard
note "Copy:  echo hi | wl-copy      Paste:  wl-paste"
note "The region-to-clipboard screenshot key now copies instead of saving."
