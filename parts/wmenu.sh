#!/bin/bash
# App launcher on Super+d. The stock sway config already binds it to
# wmenu-run, so this only installs the package.
# Usage: bash wmenu.sh [--remove]
# status: apt:wmenu
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge wmenu
    exit
fi

say "Installing wmenu"
apt_install wmenu
note "Super+d opens it. Type a program name and press Enter."
