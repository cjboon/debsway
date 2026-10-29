#!/bin/bash
# The "debsway" item at the left of the status bar: click it for a black-and-gray
# menu, in a window that fills the space under the bar (bin/debsway-menu) with Help (the key cheat sheet),
# Install apps (install-extras.sh), Update (update.sh) and Status (status.sh).
# Arrow keys and Enter choose, or click; Esc closes. What you choose runs in
# that same window. Super+? still opens the cheat sheet straight away.
# Also the debsway command (debsway --help, --update, --apps, --status...) and
# its man page, so the same things are one word away in a terminal.
# Usage: bash debsway-menu.sh [--remove]
# status: bin:debsway-menu
# files: bin/sway-status data/keys.txt
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEYS="$HOME/.local/share/debsway/keys.txt"
MAN="$HOME/.local/share/man/man1/debsway.1"

if [ "${1:-}" = --remove ]; then
    remove_snippet debsway-menu
    remove_bin debsway-menu
    remove_bin radios
    remove_bin debsway
    rm -f "$MAN"
    # rfkill goes too, unless the Bluetooth extra still needs it
    apt_purge
    # The bar keeps its "debsway" label; a click then opens the key cheat sheet
    # directly.
    exit
fi

say "Installing the debsway menu"
install_bin debsway-menu
# Wi-Fi, Bluetooth and microphone switches (the menu lists the ones this computer has).
# Wi-Fi and Bluetooth are switched with rfkill, which Debian doesn't install by
# itself; without it the menu has no Wi-Fi or Bluetooth line. It needs no sudo:
# udev gives the user at the screen /dev/rfkill.
apt_install rfkill
install_bin radios
# the debsway command and man debsway (man-db finds ~/.local/share/man from ~/.local/bin)
install_bin debsway
install -D -m 0644 "$DEBSWAY_DIR/data/debsway.1" "$MAN"
# the cheat sheet command: shows it with the menu's pager, so Esc closes it
install_bin keys
# The bar (the "debsway" item) and the cheat sheet that mentions it
install_bin sway-status
mkdir -p "${KEYS%/*}"
install -m 0644 "$DEBSWAY_DIR/data/keys.txt" "$KEYS"
# An earlier version put a window rule here; the window is sized by sway (tiled, under the bar)
remove_snippet debsway-menu
note "Click \"debsway\" in the bar: Help, Install apps, Update, Status."
note "In a terminal: debsway --help, debsway --update, debsway --apps (man debsway)."
