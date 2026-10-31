#!/bin/bash
# tmux with the sway desktop's look: a bar on top (workspace numbers, then
# debsway | wifi | vol | bright | bat | timer | date, with the same clicks), black
# and gray, Alt+1 ... Alt+0 for workspaces, Alt+m for the debsway menu. It is
# always installed, so a plain `tmux` after leaving sway looks the same, and the
# console-only extra (extras/console-only.sh) only has to start it at login.
# Inside sway (a foot window) tmux stays plain; the bar and Alt keys (console.conf)
# load only on a text console. The config goes to ~/.config/tmux/tmux.conf; one you wrote yourself is kept
# as tmux.conf.bak.
# Usage: bash console-tmux.sh [--remove]
# status: file:~/.config/tmux/tmux.conf
# files: bin/sway-status bin/console-click bin/console-font data/tmux.conf data/tmux-console.conf data/keys-console.txt
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF="$HOME/.config/tmux/tmux.conf"
MARK='Written by debsway parts/console-tmux.sh'

if [ "${1:-}" = --remove ]; then
    if grep -qs "$MARK" "$CONF"; then
        rm -f "$CONF" "${CONF%/*}/console.conf" "$HOME/.local/share/debsway/keys-console.txt"
        if [ -f "$CONF.bak" ]; then
            mv "$CONF.bak" "$CONF"
            note "Put your earlier tmux.conf back."
        fi
    fi
    remove_bin console-click
    remove_bin console-font
    apt_purge tmux
    exit
fi

say "Installing tmux"
apt_install tmux
install_bin sway-status
install_bin console-click
install_bin console-font
mkdir -p "${CONF%/*}"
if [ -f "$CONF" ] && ! grep -qs "$MARK" "$CONF" && ! cmp -s "$DEBSWAY_DIR/data/tmux.conf" "$CONF"; then
    cp "$CONF" "$CONF.bak"
    note "Your tmux.conf is kept as $CONF.bak"
fi
cp "$DEBSWAY_DIR/data/tmux.conf" "$CONF"
cp "$DEBSWAY_DIR/data/tmux-console.conf" "${CONF%/*}/console.conf"
# the key sheet for a text console (bin/keys picks it when there is no sway)
mkdir -p "$HOME/.local/share/debsway"
install -m 0644 "$DEBSWAY_DIR/data/keys-console.txt" "$HOME/.local/share/debsway/keys-console.txt"
note "Installed $CONF. On a text console tmux has the sway-like bar (Alt+m: the debsway menu); in a foot window it stays plain."
