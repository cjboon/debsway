#!/bin/bash
# Lock after 5 minutes idle, screen off after 10, lock before suspend. Half a
# minute before the lock the screen starts to fade down slowly and a
# notification says it is about to lock, so moving the mouse in time stops it
# (bin/dim-warning). Installs swaylock too, since that's what does the locking.
# Usage: bash swayidle.sh [--remove]
# status: apt:swayidle
# files: bin/dim-warning
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet idle
    pkill -x swayidle || true
    remove_bin dim-warning
    apt_purge swayidle
    exit
fi

say "Installing swayidle and swaylock"
apt_install swayidle swaylock
install_bin dim-warning

# LOCK_CMD (lib/sway.sh) is the one place that says how the screen locks
# 270 = 30 seconds before the lock at 300; the dim is undone when you come back
DIM="$HOME/.local/bin/dim-warning"
IDLE_CMD="swayidle -w timeout 270 '$DIM start' resume '$DIM stop' timeout 300 '$LOCK_CMD' timeout 600 'swaymsg \"output * power off\"' resume 'swaymsg \"output * power on\"' before-sleep '$LOCK_CMD'"

put_snippet idle <<EOF
# Idle lock and screen off (debsway parts/swayidle.sh)
exec $IDLE_CMD
EOF

# exec lines only run when sway starts, so (re)start it now if sway is up:
# a running swayidle keeps the timeouts it started with
if [ -n "${SWAYSOCK:-}" ]; then
    pkill -x swayidle || true
    swaymsg exec "$IDLE_CMD" >/dev/null && note "Started swayidle."
fi
note "The screen fades down from 270 seconds, locks at 300, turns off at 600."
note "Change the timeouts in $SWAY_SNIPPETS/idle.conf (keep the first 30 seconds before the lock)."
