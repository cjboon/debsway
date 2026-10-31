#!/bin/bash
# Console-only: log in on a text console straight into tmux, with the bar and
# keys of the sway desktop (parts/console-tmux.sh, always installed), instead of
# starting sway. Only the login changes: the sway desktop stays installed, and
# `sway` still starts it by hand. Removing this extra starts sway at login again.
# Usage: bash console-only.sh [--remove]
# summary: log in to tmux (same bar and keys), not sway
# status: file:~/.config/tmux/tmux.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    profile_autostart sway
    note "Logging in on tty1 starts sway again."
    exit
fi

say "Console-only"
# the tmux config comes with the base; make sure it is in place
bash "$DEBSWAY_DIR/parts/console-tmux.sh"
profile_autostart console
cat <<'EOT'

    Logging in on any text console now starts tmux (log out: exit the last
    window). Keys, with Alt where sway uses Super:
      Alt+1 ... Alt+0         go to workspace 1 ... 10; Alt+Shift+1 ... sends the pane
      Alt+Enter / Alt+v       split beside / below      Alt+h j k l or arrows: move
      Alt+f                   fullscreen the pane       Alt+Shift+q: close it
      Alt+m                   the debsway menu          Alt+t: timers   Alt+?: keys
      Alt+w Wi-Fi   Alt+- Alt+= volume (Alt+Backspace mutes)   Alt+, Alt+. brightness   Alt+b battery
    A text console has no mouse; used from a terminal (ssh), the bar's items also
    click and scroll as in sway. To start sway from the
    console: type  sway.
EOT
