#!/bin/bash
# A power menu on Super+Shift+Escape: lock, suspend, log out, reboot, power
# off. Shutting down is the safe state for a laptop you are leaving
# somewhere (see THREAT-MODEL.md), and this makes it one key and one choice.
# Usage: bash power-menu.sh [--remove]
# status: bin:powermenu
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet power
    remove_bin powermenu
    apt_purge wmenu
    exit
fi

say "Installing the power menu"
apt_install wmenu
install_bin powermenu

put_snippet power <<'EOF'
# Power menu (debsway parts/power-menu.sh)
bindsym $mod+Shift+Escape exec ~/.local/bin/powermenu
EOF
note "Super+Shift+Escape opens it (lock, suspend, log out, reboot, power off)."
