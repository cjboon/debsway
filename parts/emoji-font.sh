#!/bin/bash
# Color emoji in Firefox, foot and everywhere else. Without it, emoji
# show up as empty boxes.
# Usage: bash emoji-font.sh [--remove]
# status: apt:fonts-noto-color-emoji
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge fonts-noto-color-emoji
    exit
fi

say "Installing fonts-noto-color-emoji"
apt_install fonts-noto-color-emoji
note "Restart Firefox and foot to see it."
