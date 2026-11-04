#!/bin/bash
# Screen lock on Super+Escape, through wren-lock (bin/wren-lock): it locks,
# then runs the on-lock programs in ~/.config/wren/on-lock.d (the vault closes,
# KeePassXC locks), as the power menu and the lid do too.
# Usage: bash swaylock.sh [--remove]
# status: apt:swaylock
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet lock
    remove_bin wren-lock
    apt_purge swaylock
    exit
fi

say "Installing swaylock"
apt_install swaylock
install_bin wren-lock

# LOCK_CMD (lib/sway.sh) is the one place that says how the screen locks;
# wren-lock does that, then the on-lock programs
put_snippet lock <<EOF
# Lock the screen, then the on-lock programs (Wren Linux parts/swaylock.sh)
bindsym \$mod+Escape exec ~/.local/bin/wren-lock
EOF
note "Super+Escape locks. Type your password and press Enter to unlock."
