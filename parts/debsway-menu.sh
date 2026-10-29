#!/bin/bash
# The "debsway" item at the left of the status bar: click it for a small menu
# with Help (the key cheat sheet), Install apps (install-extras.sh), Update
# (update.sh) and Status (status.sh). Super+? still opens the cheat sheet
# straight away. The windows the last three open are floating terminals
# that stay open until you press Enter.
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
    # directly. wmenu is shared with the power menu and the launcher.
    apt_purge wmenu
    exit
fi

say "Installing the debsway menu"
apt_install wmenu
install_bin debsway-menu
# The bar (the "debsway" item) and the cheat sheet that mentions it
install_bin sway-status
mkdir -p "${KEYS%/*}"
install -m 0644 "$DEBSWAY_DIR/data/keys.txt" "$KEYS"

put_snippet debsway-menu <<'SNIP'
# The windows the debsway menu opens (debsway parts/debsway-menu.sh)
for_window [app_id="debsway-run"] floating enable, resize set width 80 ppt height 80 ppt
SNIP
note "Click \"debsway\" in the bar: Help, Install apps, Update, Status."
