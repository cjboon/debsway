#!/bin/bash
# Checks bin/wren-empty-workspace and its key, with a real sway of its own (headless, nothing on
# your screen) and real foot windows. Run by test.sh, or:
#   bash tools/test-empty-workspace.sh
# shellcheck disable=SC2016  # the inner shells and sway's own $mod expand their own variables
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d /tmp/wew.XXXX) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }   # (short: sway's socket path has a length limit)
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
CMD=$HERE/bin/wren-empty-workspace
P=$HERE/parts/core-commands.sh

check "it can be taken out again (remove_bin looks for this line)" grep -q 'written by Wren Linux' "$CMD"
check "the base part installs it" bash -c 'grep -q "^COMMANDS=(.* wren-empty-workspace" "$1" && sed -n "/^# files:/p" "$1" | grep -q "bin/wren-empty-workspace"' _ "$P"
# 49: the key left of 1 on any layout. A symbol (grave) is elsewhere on many keyboards.
check "...and its key goes by where the key is, left of 1, not by its symbol" grep -qx 'bindcode $mod+49 exec ~/.local/bin/wren-empty-workspace' "$P"
check "...and takes the key out again" bash -c 'sed -n "/--remove ]; then/,/^fi/p" "$1" | grep -q "remove_snippet empty-workspace"' _ "$P"
check "the key sheet says so, with the other workspace keys" bash -c 'sed -n "/^  WORKSPACES/,/^@end/p" "$1" | grep -q "the key left of 1"' _ "$HERE/data/keys.txt"

if ! command -v sway >/dev/null || ! command -v foot >/dev/null || ! command -v python3 >/dev/null; then
    echo "  (no sway, foot or python3 here: not tried in a real sway)"
    rm -rf "$T"
    [ "$fails" -eq 0 ]
    exit
fi

mkdir -p "$T/bin" "$T/home/.config/sway/config.d"
printf 'set $mod Mod4\nxwayland disable\nbindcode $mod+49 exec true\n' >"$T/config"
out=$(WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 XDG_RUNTIME_DIR=$T sway -C -c "$T/config" 2>&1)
check "a real sway takes that key" not grep -q '\[ERROR\]' <<<"$out"
printf '#!/bin/sh\necho "$*" >>"%s/notified"\n' "$T" >"$T/bin/notify-send"
chmod +x "$T/bin/notify-send"
XDG_RUNTIME_DIR=$T WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -c "$T/config" >/dev/null 2>&1 &
swaypid=$!
i=0
while [ "$i" -lt 50 ] && ! ls "$T"/sway-ipc.* >/dev/null 2>&1; do /bin/sleep 0.2; i=$((i + 1)); done
sock=$(ls "$T"/sway-ipc.* 2>/dev/null)
disp=
for f in "$T"/wayland-[0-9]*; do case $f in *.lock) ;; *) disp=${f##*/} ;; esac; done
windows=()
cleanup() {
    for w in "${windows[@]}"; do kill "$w" 2>/dev/null; done
    kill "$swaypid" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT
sm() { XDG_RUNTIME_DIR=$T SWAYSOCK=$sock swaymsg "$@"; }
here() { sm -t get_workspaces | python3 -I -c 'import json, sys; print([w["num"] for w in json.load(sys.stdin) if w["focused"]][0])'; }
press() { env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_RUNTIME_DIR="$T" SWAYSOCK="$sock" PATH="$T/bin:$PATH" sh "$CMD"; }
# busy N: a real window on workspace N
busy() {
    sm "workspace number $1" >/dev/null
    XDG_RUNTIME_DIR=$T WAYLAND_DISPLAY=$disp foot --title="busy$1" /bin/sleep 120 >/dev/null 2>&1 &
    windows+=($!)
    local i=0
    until sm -t get_tree | grep -q "\"name\": \"busy$1\"" || [ "$i" -ge 50 ]; do /bin/sleep 0.2; i=$((i + 1)); done
}

press
check "no windows at all: workspace 1, the first empty one" test "$(here)" = 1
busy 1
press
check "only 1 in use: it goes to 2" test "$(here)" = 2
press
check "...pressed again, on that empty one: it stays" test "$(here)" = 2
busy 2
busy 4
busy 5
sm "workspace number 1" >/dev/null
press
check "1, 2, 4 and 5 in use: it goes to 6, after the highest, from wherever you are" test "$(here)" = 6
: >"$T/home/.config/sway/config.d/one-workspace.conf"
sm "workspace number 1" >/dev/null
press
check "with the one-workspace extra: it does nothing" test "$(here)" = 1
rm -f "$T/home/.config/sway/config.d/one-workspace.conf"
busy 10
sm "workspace number 2" >/dev/null
press
check "10 in use: there is no next one, so it stays where you are" test "$(here)" = 2
check "...and says so" grep -q 'No empty workspace' "$T/notified"

[ "$fails" -eq 0 ]
