#!/bin/bash
# The small commands the base desktop installs for itself: keys (the cheat
# sheet), debsway-welcome (its first-login screen), timer, display-scale and
# sway-status (the bar). install-base.sh puts them in place while it sets sway
# up; this part does the same again so that debsway --update, which only reruns
# parts and extras, can bring them up to date when they change. It also
# installs ncal, whose cal draws the month in timer's screen.
# Usage: bash core-commands.sh [--remove]
# status: bin:timer
# files: data/keys.txt data/alarm.wav
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEYS="$HOME/.local/share/debsway/keys.txt"
COMMANDS=(keys debsway-welcome timer display-scale sway-status)

if [ "${1:-}" = --remove ]; then
    warn "These are what the desktop's keys, bar and first-login screen run."
    for c in "${COMMANDS[@]}"; do remove_bin "$c"; done
    rm -f "$KEYS" "${KEYS%/*}/alarm.wav"
    apt_purge ncal
    exit
fi

say "The base desktop's commands"
# cal and ncal: the month in the timer screen (click the time in the bar)
apt_install ncal
for c in "${COMMANDS[@]}"; do install_bin "$c"; done
mkdir -p "${KEYS%/*}"
install -m 0644 "$DEBSWAY_DIR/data/keys.txt" "$KEYS"
note "Cheat sheet: $KEYS"
# The sound timer and alarm clock ring with: three short beeps (tools/make-alarm-sound.py)
install -m 0644 "$DEBSWAY_DIR/data/alarm.wav" "${KEYS%/*}/alarm.wav"
