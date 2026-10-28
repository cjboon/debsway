#!/bin/bash
# Checks bin/media-sandbox with a pretend bubblewrap and a pretend
# wayland-restrict that only write down how they were called: what the
# program is shown, and which kinds of address switch the network on.
# Changes nothing. Run by test.sh, or:  bash tools/test-media-sandbox.sh
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

mkdir -p "$T/fake" "$T/run" "$T/home"
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >"%s/bwrap.args"\n' "$T" >"$T/fake/bwrap"
# wayland-restrict: say it is ready, then wait until its input closes
printf '#!/bin/sh\necho ready\ncat >/dev/null\n' >"$T/fake/wayland-restrict"
chmod +x "$T/fake/"*
echo x >"$T/video.mp4"
export PATH="$T/fake:$PATH" HOME="$T/home" XDG_RUNTIME_DIR="$T/run" WAYLAND_DISPLAY=wayland-1
: >"$T/run/wayland-1"

run() { rm -f "$T/bwrap.args"; bash "$HERE/bin/media-sandbox" "$@"; }
args() { cat "$T/bwrap.args"; }

run mpv "$T/video.mp4"
check "a file on the command line is shown to the program" grep -qxF "$T/video.mp4" "$T/bwrap.args"
check "a file alone gives no network" not grep -qx -e --share-net "$T/bwrap.args"
check "the program gets the restricted socket, not the real one" not grep -qxF "$T/run/wayland-1" <(grep -A1 -x -e --ro-bind "$T/bwrap.args" | grep -v -e '^--')

run mpv https://example.org/v.mp4
check "an https address turns the network on" grep -qx -e --share-net "$T/bwrap.args"

run mpv "file://$T/video.mp4"
check "a file:// address is shown as the file" grep -qxF "$T/video.mp4" "$T/bwrap.args"
check "a file:// address gives no network" not grep -qx -e --share-net "$T/bwrap.args"

run mpv "--sub-file=file://$T/video.mp4"
check "an option with a file:// address gives no network" not grep -qx -e --share-net "$T/bwrap.args"

run mpv "--sub-file=https://example.org/s.srt"
check "an option with an https address turns the network on" grep -qx -e --share-net "$T/bwrap.args"

[ "$fails" -eq 0 ]
