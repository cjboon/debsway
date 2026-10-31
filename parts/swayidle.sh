#!/bin/bash
# Lock after 30 minutes idle, screen off 5 minutes later, lock before suspend.
# Half a minute before the lock the screen starts to fade down slowly and a
# notification says it is about to lock, so moving the mouse in time stops it
# (bin/dim-warning). Installs swaylock too, since that's what does the locking.
# Change the time with  timer lock MINUTES  (bin/debsway-idle reads it, so
# running this again keeps your choice).
# Usage: bash swayidle.sh [--remove]
# status: apt:swayidle
# files: bin/dim-warning
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet idle
    pkill -x swayidle || true
    remove_bin dim-warning
    remove_bin debsway-idle
    apt_purge swayidle
    exit
fi

say "Installing swayidle and swaylock"
apt_install swayidle swaylock
install_bin dim-warning
# swayidle with the timeouts: the lock time comes from timer lock
install_bin debsway-idle
IDLE_CMD="$HOME/.local/bin/debsway-idle"

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
note "The screen locks after $("$IDLE_CMD" --minutes) minutes idle (fading down for the 30 seconds"
note "before), and turns off 5 minutes later. Change the time: timer lock 10"
