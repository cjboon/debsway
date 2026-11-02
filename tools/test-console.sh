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
swap console
check "console-only sets the mode to console" grep -qx console "$HOME/.config/debsway/login"
check "twice leaves one block" test "$(grep -c 'debsway autostart >>>' "$HOME/.profile")" = 1
swap sway
check "removing it sets sway again" grep -qx sway "$HOME/.config/debsway/login"
check "login_mode reads it" test "$(bash -c ". '$HERE/lib/core.sh'; login_mode")" = sway
# the block's loop: a pretend tmux/sway on a pretend tty; changing the mode while one runs starts the other
mkdir -p "$T/lb"
printf '#!/bin/sh\necho /dev/tty1\n' >"$T/lb/tty"
printf '#!/bin/sh\necho sway >>%s/ran; echo console >%s/home/.config/debsway/login\n' "$T" "$T" >"$T/lb/env"
printf '#!/bin/sh\necho tmux >>%s/ran\n' "$T" >"$T/lb/tmux"
chmod +x "$T"/lb/*
rm -f "$T/ran"
swap sway
sed -n '/^case "\$(tty/,/^esac/p' "$HOME/.profile" | sed 's|/dev/tty\[0-9\]\*|*|' >"$T/block.sh"
PATH=$T/lb:$PATH bash -c 'unset WAYLAND_DISPLAY TMUX; . "$1"' _ "$T/block.sh" >/dev/null 2>&1
check "ending sway after the mode changed to console starts tmux" test "$(cat "$T/ran")" = "$(printf 'sway\ntmux')"

# extras/console-only.sh itself, in a copy of debsway with a pretend sudo, swaymsg
# and sleep, and the base's tmux part stubbed out
R=$T/r
mkdir -p "$R/extras" "$R/parts" "$T/cb"
sed 's|^export PATH=.*|export PATH="$CONSOLE_TEST_PATH"|' "$HERE/lib.sh" >"$R/lib.sh"
for f in pins.sh packages.sh lib data docs bin; do ln -s "$HERE/$f" "$R/$f"; done
cp "$HERE/extras/console-only.sh" "$R/extras/"
printf 'mkdir -p "$HOME/.config/tmux"; : >"$HOME/.config/tmux/tmux.conf"\n' >"$R/parts/console-tmux.sh"
printf '#!/bin/sh\n[ "$1" = -v ] && exit 0\n' >"$T/cb/sudo"
printf '#!/bin/sh\necho "swaymsg $*" >>"%s/sway-calls"\n' "$T" >"$T/cb/swaymsg"
printf '#!/bin/sh\n' >"$T/cb/sleep"
chmod +x "$T"/cb/*
export CONSOLE_TEST_PATH="$T/cb:$PATH"
co() { : >"$T/sway-calls"; WAYLAND_DISPLAY=wayland-1 DEBSWAY_LOGIN_LOOP=1 bash "$R/extras/console-only.sh" "$@" >/dev/null 2>&1; }
found() { (cd "$R" && bash -c '. ./lib.sh; script_found extras/console-only.sh'); }
rm -rf "$HOME/.config"; swap sway
mkdir -p "$HOME/.config/tmux"; : >"$HOME/.config/tmux/tmux.conf"
check "console-only: the base's tmux config alone doesn't count as it being set up" test -z "$(found)"
co
check "set up from inside sway: the login is tmux, and sway is left" bash -c 'grep -qx console "$1" && grep -qx "swaymsg exit" "$2"' _ "$HOME/.config/debsway/login" "$T/sway-calls"
check "...and it counts as set up" test -n "$(found)"
co
check "run again (as update.sh does) from a sway started by hand: sway stays" not grep -q 'swaymsg exit' "$T/sway-calls"
co --remove
check "--remove: no longer counted as set up, and the login is sway" bash -c '[ -z "$1" ] && grep -qx sway "$2"' _ "$(found)" "$HOME/.config/debsway/login"

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
