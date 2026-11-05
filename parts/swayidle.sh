#!/bin/bash
# Screen off after 5 minutes idle (sway's own default), locked a minute later
# (the vault and KeePassXC with it): back within the minute, any key brings it
# back without a password. Locked at once before suspend.
# Half a minute before the screen turns off it starts to fade down slowly and a
# notification says so, so moving the mouse in time stops it
# (bin/dim-warning). Installs swaylock too, since that's what does the locking.
# Change the time with  timer lock MINUTES  (bin/wren-idle reads it, so
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
    remove_bin wren-idle
    apt_purge swayidle
    exit
fi

say "Installing swayidle and swaylock"
apt_install swayidle swaylock
install_bin dim-warning
# swayidle with the timeouts: the time comes from timer lock
install_bin wren-idle
IDLE_CMD="$HOME/.local/bin/wren-idle"

put_snippet idle <<EOF
# Idle lock and screen off (Wren Linux parts/swayidle.sh)
exec $IDLE_CMD
EOF

# exec lines only run when sway starts, so (re)start it now if sway is up:
# a running swayidle keeps the timeouts it started with
if [ -n "${SWAYSOCK:-}" ]; then
    pkill -x swayidle || true
    swaymsg exec "$IDLE_CMD" >/dev/null && note "Started swayidle."
fi
note "The screen turns off after $("$IDLE_CMD" --minutes) minutes idle (fading down for the 30 seconds"
note "before) and locks a minute later; back within that minute, any key brings it back"
note "without a password. Change the time: timer lock 10"
