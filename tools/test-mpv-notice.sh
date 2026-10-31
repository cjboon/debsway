#!/bin/bash
# Checks the one-time "no sound" notice in bin/mpv, with a pretend media-sandbox
# and notify-send. Changes nothing. Run by test.sh, or:  bash tools/test-mpv-notice.sh
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

mkdir -p "$T/home/.local/bin" "$T/run" "$T/fake"
# shellcheck disable=SC2016  # written into the pretend programs, expanded when they run
printf '#!/bin/sh\necho "sandbox $*" >>"%s/ran"\n' "$T" >"$T/home/.local/bin/media-sandbox"
# shellcheck disable=SC2016
printf '#!/bin/sh\necho "$*" >>"%s/notified"\n' "$T" >"$T/fake/notify-send"
chmod +x "$T/home/.local/bin/media-sandbox" "$T/fake/notify-send"
mpv() { env HOME="$T/home" XDG_RUNTIME_DIR="$T/run" XDG_STATE_HOME="$T/state" PATH="$T/fake:$PATH" sh "$HERE/bin/mpv" "$@"; }

: >"$T/ran"; : >"$T/notified"
out=$(mpv video.mp4 2>&1)
check "without a sound server the first start says so" grep -q 'No sound package is installed' <<<"$out"
check "...tells how to add it, without offering to install it" grep -q 'debsway --apps' <<<"$out"
check "...with a desktop notification too" grep -q 'mpv has no sound' "$T/notified"
check "...and mpv still starts" grep -q 'sandbox /usr/bin/mpv video.mp4' "$T/ran"
: >"$T/notified"
out=$(mpv again.mp4 2>&1)
check "the second start says nothing" not grep -q 'No sound' <<<"$out"
check "...and sends no notification" test ! -s "$T/notified"

rm -rf "$T/state"; : >"$T/notified"
python3 -I -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.bind(sys.argv[1]); import time; time.sleep(3)' "$T/run/pipewire-0" &
sleep 0.3
out=$(mpv third.mp4 2>&1)
check "with a sound server running it says nothing" not grep -q 'No sound' <<<"$out"
check "...and does not use up the one notice" test ! -e "$T/state/debsway/mpv-no-sound"
kill $! 2>/dev/null

[ "$fails" -eq 0 ]
