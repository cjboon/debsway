#!/bin/bash
# The "debsway" item at the left of the status bar: click it for a black-and-gray
# menu, in a window that fills the space under the bar (bin/debsway-menu) with Help (the key cheat sheet),
# Install apps (install-extras.sh), Update (update.sh) and Status (status.sh).
# Arrow keys and Enter choose, or click; Esc closes. What you choose runs in
# that same window. Super+? still opens the cheat sheet straight away.
# Usage: bash debsway-menu.sh [--remove]
# status: bin:debsway-menu
# files: bin/sway-status data/keys.txt
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEYS="$HOME/.local/share/debsway/keys.txt"

if [ "${1:-}" = --remove ]; then
    remove_snippet debsway-menu
    remove_bin debsway-menu
    # The bar keeps its "debsway" label; a click then opens the key cheat sheet
    # directly.
    exit
fi

say "Installing the debsway menu"
install_bin debsway-menu
# the cheat sheet command: shows it with the menu's pager, so Esc closes it
install_bin keys
# The bar (the "debsway" item) and the cheat sheet that mentions it
install_bin sway-status
mkdir -p "${KEYS%/*}"
install -m 0644 "$DEBSWAY_DIR/data/keys.txt" "$KEYS"
# An earlier version put a window rule here; the window is sized by sway (tiled, under the bar)
remove_snippet debsway-menu
note "Click \"debsway\" in the bar: Help, Install apps, Update, Status."
