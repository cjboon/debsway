#!/bin/bash
# App launcher on Super+d. The stock sway config already binds it to
# wmenu-run; this installs the package and gives the launcher debsway's look:
# the bar's black and white, opaque (the bar is see-through, so a see-through
# launcher would show it underneath), and a font a little larger than the
# bar's so the launcher covers the bar completely (lib/sway.sh, LAUNCHER_STYLED).
# Usage: bash wmenu.sh [--remove]
# status: apt:wmenu
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    if [ -f "$SWAY_CONFIG" ] && grep -qxF "$LAUNCHER_STYLED" "$SWAY_CONFIG"; then
        unstyle_launcher "$SWAY_CONFIG"
        reload_sway
    fi
    apt_purge wmenu
    exit
fi

say "Installing wmenu"
apt_install wmenu
ensure_sway_config
if style_launcher "$SWAY_CONFIG"; then
    check_sway_config || { unstyle_launcher "$SWAY_CONFIG"; die "sway rejected the launcher line, so the stock one was put back."; }
    reload_sway
    note "Super+d opens it in debsway's colors. Type a program name and press Enter."
else
    note "Your \$menu line in $SWAY_CONFIG isn't the stock one, so it was left alone."
    note "Super+d opens it. Type a program name and press Enter."
fi
