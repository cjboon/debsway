#!/bin/bash
# Console-only: log in on a text console straight into tmux, with the bar and
# keys of the sway desktop (parts/console-tmux.sh, always installed), instead of
# starting sway. Only the login changes: the sway desktop stays installed, and
# `sway` still starts it by hand. Removing this extra starts sway at login again.
# Both happen at once: installing it from inside sway ends sway and drops you into
# tmux; removing it from inside tmux detaches and starts sway (login loop in
# ~/.profile, lib/core.sh profile_autostart). Run again while it is set up (as
# update.sh does), it leaves whatever is running alone.
# Usage: bash console-only.sh [--remove | --manual]
# summary: log in to tmux (same bar and keys), not sway
# security: some
# status: file:~/.config/wren/console-only
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

# Set up: this file (the tmux config is the base's, so it can't say)
MARK=$HOME/.config/wren/console-only

if [ "${1:-}" = --remove ]; then
    # sway first, the mark last: a removal cut off half way still shows as
    # set up, and --remove again finishes it (it once left the login on tmux)
    profile_autostart sway
    rm -f "$MARK"
    note "Logging in on tty1 starts sway again."
    if [ -n "${TMUX:-}" ] && [ -n "${WREN_LOGIN_LOOP:-}" ]; then
        note "Leaving tmux for sway in 3 seconds (your tmux windows stay: tmux attach)..."
        sleep 3
        tmux detach-client -s "$(tmux display-message -p '#S')"
    elif [ -n "${TMUX:-}" ]; then
        note "Log out and in on tty1 to get sway."
    fi
    exit
fi

say "Console-only"
# the tmux config comes with the base; make sure it is in place
bash "$WREN_DIR/parts/console-tmux.sh"
# Only a switch from sway to tmux leaves sway; a run again (update.sh) doesn't
was=$(login_mode)
profile_autostart console
mkdir -p "${MARK%/*}"
printf '%s\n' '# Written by Wren Linux extras/console-only.sh: logging in starts tmux, not sway.' >"$MARK"
cat <<'EOT'

    Logging in on any text console now starts tmux (log out: exit the last
    window). Keys, with Alt where sway uses Super:
      Alt+1 ... Alt+0         go to workspace 1 ... 10; Alt+Shift+1 ... sends the pane
      Alt+Enter / Alt+v       split beside / below      Alt+h j k l or arrows: move
      Alt+f                   fullscreen the pane       Alt+Shift+q: close it
      Alt+m                   the Wren menu          Alt+t: timers   Alt+?: keys
      Alt+w Wi-Fi   Alt+- Alt+= volume (Alt+Backspace mutes)   Alt+, Alt+. brightness   Alt+b battery
    A text console has no mouse; used from a terminal (ssh), the bar's items also
    click and scroll as in sway. To start sway from the
    console: type  sway.
EOT

if [ "$was" != console ] && [ -n "${WAYLAND_DISPLAY:-}" ] && command -v swaymsg >/dev/null; then
    if [ -n "${WREN_LOGIN_LOOP:-}" ]; then
        note "Leaving sway for the console in 3 seconds (programs in sway close)..."
        sleep 3
        swaymsg exit
    else
        note "Log out of sway (Super+Shift+e) and log in on tty1 to get the console."
    fi
fi
