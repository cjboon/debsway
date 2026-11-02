#!/bin/bash
# Checks status.sh's Screen lock line: it says the screen never locks when
# swaylock isn't installed, whatever the idle settings say. status.sh only
# reads; it runs here in a temp home, once with swaylock, once with a PATH
# that has everything else. Run by test.sh, or:  bash tools/test-status.sh
# shellcheck disable=SC2016  # sed expands its own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }

# A copy of debsway whose lib.sh keeps the test's PATH
R=$T/r
mkdir -p "$R" "$T/home/.config/sway/config.d" "$T/home/.local/bin" "$T/bin" "$T/nolock"
for f in "$HERE"/*; do [ "${f##*/}" = lib.sh ] || ln -s "$f" "$R/${f##*/}"; done
sed 's|^export PATH=.*|export PATH="$STATUS_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
grep -q STATUS_TEST_PATH "$R/lib.sh" || { echo "  FAIL  lib.sh's PATH line wasn't found"; exit 1; }
# The idle lock is set up, for 30 minutes
: >"$T/home/.config/sway/config.d/idle.conf"
printf '#!/bin/sh\necho 30\n' >"$T/home/.local/bin/debsway-idle"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/swaylock"
chmod +x "$T/home/.local/bin/debsway-idle" "$T/bin/swaylock"
# Every program of /usr/bin and /usr/sbin but swaylock
for d in /usr/bin /usr/sbin; do
    for f in "$d"/*; do [ "${f##*/}" = swaylock ] || [ -e "$T/nolock/${f##*/}" ] || ln -s "$f" "$T/nolock/${f##*/}"; done
done
lockline() { HOME=$T/home STATUS_TEST_PATH=$1 bash "$R/status.sh" 2>/dev/null | sed -n '/^Screen lock:/{n;p}'; }

check "with swaylock: it locks after the idle minutes" grep -q 'after 30 minutes idle' <<<"$(lockline "$T/bin:$T/nolock")"
check "without swaylock: it says the screen never locks" grep -q "swaylock isn't installed, so the screen never locks" <<<"$(lockline "$T/nolock")"

[ "$fails" -eq 0 ]
