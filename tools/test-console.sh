#!/bin/bash
# Checks the console-only pieces: the ~/.profile autostart swap (sway <-> tmux),
# the tmux bar text of bin/sway-status, and bin/console-click with a pretend
# tmux. Changes nothing outside a temp folder. Run by test.sh, or:
#   bash tools/test-console.sh
# shellcheck disable=SC2016  # the inner bash expands its own variables
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

export HOME=$T/home
mkdir -p "$HOME"
swap() { bash -c ". '$HERE/lib/core.sh'; profile_autostart $1" >/dev/null 2>&1; }
swap sway
check "sway autostart is written" grep -q 'debsway autostart >>>' "$HOME/.profile"
swap console
check "console-only swaps it for tmux" grep -q 'exec tmux new-session' "$HOME/.profile"
check "...and the sway block is gone" not grep -q 'exec env XDG_CURRENT_DESKTOP=sway sway' "$HOME/.profile"
swap console
check "twice leaves one block" test "$(grep -c 'debsway console >>>' "$HOME/.profile")" = 1
swap sway
check "removing it starts sway again" grep -q 'exec env XDG_CURRENT_DESKTOP=sway sway' "$HOME/.profile"
check "...and tmux is gone" not grep -q 'exec tmux' "$HOME/.profile"

bar=$(sh "$HERE/bin/sway-status" --tmux)
check "the tmux bar starts with the debsway menu range" bash -c '[[ $1 == "#[range=user|menu]debsway#[norange]"* ]]' _ "$bar"
check "...and has a date item" bash -c '[[ $1 == *"#[range=user|date]"* ]]' _ "$bar"

mkdir -p "$T/bin" "$HOME/.local/bin"
printf '#!/bin/sh\necho "$@" >>%s/calls\n' "$T" >"$T/bin/tmux"
chmod +x "$T/bin/tmux"
printf '#!/bin/sh\necho "volume $@" >>%s/calls\n' "$T" >"$HOME/.local/bin/volume"
chmod +x "$HOME/.local/bin/volume"
PATH=$T/bin:$PATH sh "$HERE/bin/console-click" menu 1 c0
check "a click on debsway opens the menu in a pop-up" grep -q 'display-popup -c c0 -E -w 72% -h 85% .*debsway-menu --tui' "$T/calls"
PATH=$T/bin:$PATH sh "$HERE/bin/console-click" vol 4 c0
check "scrolling vol up raises the volume" grep -qx 'volume up' "$T/calls"
check "the config loads the console file only without sway" grep -q "if-shell '\[ -z \"\$WAYLAND_DISPLAY\" \]' 'source-file ~/.config/tmux/console.conf'" "$HERE/data/tmux.conf"
check "Alt+3 and Alt+Shift+3 are bound" bash -c 'grep -q "M-3 " "$1" && grep -q "M-#" "$1"' _ "$HERE/data/tmux-console.conf"
check "Alt+w, volume and brightness keys are bound" bash -c 'grep -q "M-w " "$1" && grep -q "M-= " "$1" && grep -q "M-\. " "$1"' _ "$HERE/data/tmux-console.conf"

[ "$fails" -eq 0 ] || { echo "$fails failed"; exit 1; }
