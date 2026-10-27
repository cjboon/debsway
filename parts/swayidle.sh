#!/bin/bash
# Lock after 5 minutes idle, screen off after 10, lock before suspend.
# Installs swaylock too, since that's what does the locking.
# Usage: bash swayidle.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet idle
    pkill -x swayidle || true
    apt_purge swayidle
    exit
fi

say "Installing swayidle and swaylock"
apt_install swayidle swaylock

IDLE_CMD="swayidle -w timeout 300 'swaylock -f -c 000000' timeout 600 'swaymsg \"output * power off\"' resume 'swaymsg \"output * power on\"' before-sleep 'swaylock -f -c 000000'"

put_snippet idle <<EOF
# Idle lock and screen off (debsway parts/swayidle.sh)
exec $IDLE_CMD
EOF

# exec lines only run when sway starts, so start it now if sway is up
if [ -n "${SWAYSOCK:-}" ] && ! pgrep -x swayidle >/dev/null; then
    swaymsg exec "$IDLE_CMD" >/dev/null && note "Started swayidle."
fi
note "Change the 300/600 second timeouts in $SWAY_SNIPPETS/idle.conf"
