#!/bin/bash
# Screen lock on Super+Escape.
# Usage: bash swaylock.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet lock
    apt_purge swaylock
    exit
fi

say "Installing swaylock"
apt_install swaylock

put_snippet lock <<'EOF'
# Lock the screen (debsway parts/swaylock.sh)
bindsym $mod+Escape exec swaylock -f -c 000000
EOF
note "Super+Escape locks. Type your password and press Enter to unlock."
