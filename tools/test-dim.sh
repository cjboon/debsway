#!/bin/bash
# Checks bin/wren-dim with a real sway of its own (headless, nothing on your screen) and real foot
# windows, reading what sway really draws, with grim. Run by test.sh, or:  bash tools/test-dim.sh
# shellcheck disable=SC2016  # the inner shells expand their own variables
# shellcheck disable=SC2086  # $L and $R are two numbers each, split on purpose
HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d /tmp/wdm.XXXX) || { echo "  FAIL  couldn't make a temp folder (is /tmp full?)"; exit 1; }   # (short: sway's socket path has a length limit)
fails=0
check() { # DESCRIPTION CONDITION-COMMAND...
    local what=$1
    shift
    if "$@" >/dev/null 2>&1; then printf '  ok    %s\n' "$what"; else printf '  FAIL  %s\n' "$what"; fails=$((fails + 1)); fi
}
not() { ! "$@"; }
CMD=$HERE/bin/wren-dim
P=$HERE/parts/core-commands.sh
check "it can be taken out again (remove_bin looks for this line)" grep -q 'written by Wren Linux' "$CMD"
check "the base part installs and starts it" bash -c 'grep -q "^COMMANDS=(.* wren-dim" "$1" && grep -qx "exec ~/.local/bin/wren-dim" "$1"' _ "$P"
check "...and takes it out again" bash -c 'sed -n "/--remove ]; then/,/^fi/p" "$1" | grep -q "remove_snippet dim"' _ "$P"
if ! command -v sway >/dev/null || ! command -v foot >/dev/null || ! command -v python3 >/dev/null || ! command -v grim >/dev/null; then
    echo "  (no sway, foot, grim or python3 here: not tried in a real sway)"
    rm -rf "$T"
    [ "$fails" -eq 0 ]
    exit
fi
mkdir -p "$T/home/.config"
printf 'xwayland disable\ndefault_border none\noutput * bg #ffffff solid_color\ndefault_floating_border none\nfor_window [title="pop"] floating enable, resize set 300 200, move position 50 50\nfor_window [title="glass"] opacity 0.85\n' >"$T/config"
XDG_RUNTIME_DIR=$T WLR_BACKENDS=headless WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 sway -c "$T/config" >/dev/null 2>&1 &
swaypid=$!
i=0
while [ "$i" -lt 50 ] && ! ls "$T"/sway-ipc.* >/dev/null 2>&1; do /bin/sleep 0.2; i=$((i + 1)); done
sock=$(ls "$T"/sway-ipc.* 2>/dev/null)
disp=
for f in "$T"/wayland-[0-9]*; do case $f in *.lock) ;; *) disp=${f##*/} ;; esac; done
windows=()
cleanup() {
    dim off 2>/dev/null
    for w in "${windows[@]}"; do kill "$w" 2>/dev/null; done
    kill "$swaypid" 2>/dev/null
    wait 2>/dev/null
    rm -rf "$T"
}
trap cleanup EXIT
sm() { XDG_RUNTIME_DIR=$T SWAYSOCK=$sock swaymsg "$@"; }
dim() { env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" XDG_RUNTIME_DIR="$T" SWAYSOCK="$sock" sh "$CMD" "$@" </dev/null >"$T/dim.out" 2>&1; }
# a window, black all over: foot's background, so what shows through can be measured
win() {
    XDG_RUNTIME_DIR=$T WAYLAND_DISPLAY=$disp foot -o colors.background=000000 -o colors.alpha=1 --title="$1" /bin/sleep 120 >/dev/null 2>&1 &
    windows+=($!)
    local i=0
    until sm -t get_tree | grep -q "\"name\": \"$1\"" || [ "$i" -ge 50 ]; do /bin/sleep 0.2; i=$((i + 1)); done
}
# shade X Y: how bright the screen is there, 0 (a black window at full strength) to 255 (the white behind)
shade() {
    /bin/sleep 0.6
    XDG_RUNTIME_DIR=$T WAYLAND_DISPLAY=$disp grim -t ppm -g "$1,$2 1x1" - | tail -c 3 | od -An -tu1 | awk '{print $1}'
}
is_clear() { [ "$1" -le 8 ]; }
faded() { [ "$1" -ge 50 ] && [ "$1" -le 120 ]; }   # 0.3 of white is about 76
focus() { sm "[title=\"$1\"] focus" >/dev/null; }
win left
win right
# (1280x720 at most, headless; two windows side by side)
L="100 400" R="900 400"
b=$(shade $L)
check "before it runs: both windows solid" is_clear "$b"
XDG_RUNTIME_DIR=$T env HOME="$T/home" XDG_CONFIG_HOME="$T/home/.config" SWAYSOCK="$sock" sh "$CMD" </dev/null >/dev/null 2>&1 &
i=0
while [ "$i" -lt 30 ] && [ ! -s "$T/wren-dim.pid" ]; do /bin/sleep 0.2; i=$((i + 1)); done
check "the focused window stays solid" is_clear "$(shade $R)"
check "...and the other fades" faded "$(shade $L)"
focus left
check "focus the other: they swap" bash -c 'is() { [ "$1" -le 8 ]; }; f() { [ "$1" -ge 50 ] && [ "$1" -le 120 ]; }; is "$1" && f "$2"' _ "$(shade $L)" "$(shade $R)"
sm "workspace number 2" >/dev/null
win alone
check "a window alone on its workspace: solid" is_clear "$(shade 640 400)"
sm "workspace number 1" >/dev/null
check "back: it is as it was" bash -c '[ "$1" -le 8 ] && [ "$2" -ge 50 ]' _ "$(shade $L)" "$(shade $R)"
# A window filling the workspace, and a pop-up over it, both ways
sm "workspace number 3" >/dev/null
win big
win pop
check "a pop-up with the focus: solid" is_clear "$(shade 100 100)"
check "...and the window under it fades" faded "$(shade 900 500)"
focus big
check "the window under it with the focus: solid" is_clear "$(shade 900 500)"
sm "workspace number 4" >/dev/null
win glass
win other
focus other
fadedglass=$(shade 100 400)
focus glass
solidglass=$(shade 100 400)
check "a window see-through of its own: it stays so with the focus, and fades further without" bash -c '[ "$1" -ge 25 ] && [ "$1" -le 60 ] && [ "$2" -gt "$1" ]' _ "$solidglass" "$fadedglass"
sm "[title=\"other\"] kill" >/dev/null
/bin/sleep 0.5
focus glass
check "a window closing doesn't upset it" bash -c 'grep -q . "$1"' _ "$T/wren-dim.pid"
dim 0.5
sm "workspace number 1" >/dev/null
check "wren-dim 0.5: fades that much" bash -c '[ "$1" -ge 110 ] && [ "$1" -le 145 ]' _ "$(shade $R)"
check "...and it's kept" grep -qx 0.5 "$T/home/.config/wren/dim"
dim status
check "status says so" grep -q 'on, fading 0.5' "$T/dim.out"
dim nonsense; rc=$?
check "nonsense: refused" test "$rc" = 2
check "...nothing changed" grep -qx 0.5 "$T/home/.config/wren/dim"
dim off
check "off: every window solid again" is_clear "$(shade $R)"
check "...and stays off: it won't start at the next login" bash -c 'env HOME="$1/home" XDG_CONFIG_HOME="$1/home/.config" XDG_RUNTIME_DIR="$1" SWAYSOCK="$2" sh "$3" </dev/null; [ ! -e "$1/wren-dim.pid" ]' _ "$T" "$sock" "$CMD"
dim on
/bin/sleep 0.5
check "on: again" faded "$(shade $R)"
[ "$fails" -eq 0 ]
