#!/bin/bash
# The "debsway" item at the left of the status bar: click it for a black-and-gray
# menu, in a floating, centered window (bin/debsway-menu) with Help (the key cheat sheet),
# Install apps (install-extras.sh), Update (update.sh) and Status (status.sh).
# Arrow keys and Enter choose, or click; Esc closes. What you choose runs in
# that same window. Super+? still opens the cheat sheet straight away.
# Also the debsway command (debsway --help, --update, --apps, debsway install
# NAME...), its man page and its Tab completion, so the same things are one
# word away in a terminal.
# Usage: bash debsway-menu.sh [--remove]
# status: bin:debsway-menu
# files: bin/sway-status data/keys.txt
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEYS="$HOME/.local/share/debsway/keys.txt"
MAN="$HOME/.local/share/man/man1/debsway.1"
# where Debian's bash-completion looks for a user's own completions
COMPLETION="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/debsway"

if [ "${1:-}" = --remove ]; then
    remove_snippet debsway-menu
    remove_bin debsway-menu
    remove_bin radios
    remove_bin debsway
    rm -f "$MAN" "$COMPLETION"
    # rfkill goes too, unless another script still needs it
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
# (dialog drew the Install apps list for a while; lib/checklist.sh does now,
# with no program of its own, so this script no longer wants it)
apt_drop dialog
apt_install rfkill
install_bin radios
# the debsway command and man debsway (man-db finds ~/.local/share/man from ~/.local/bin)
install_bin debsway
install -D -m 0644 "$DEBSWAY_DIR/data/debsway.1" "$MAN"
# Tab completes debsway install NAME (and the options) in a new terminal
install -D -m 0644 "$DEBSWAY_DIR/data/debsway-completion.bash" "$COMPLETION"
# the cheat sheet command: shows it with the menu's pager, so Esc closes it
install_bin keys
# The bar (the "debsway" item) and the cheat sheet that mentions it
install_bin sway-status
mkdir -p "${KEYS%/*}"
install -m 0644 "$DEBSWAY_DIR/data/keys.txt" "$KEYS"
# Super+m, as a click on "debsway" in the bar: again closes it. Here, not in
# install-base.sh, so update.sh brings it to an install made before it (an
# earlier version's window rule in this snippet now lives in install-base.sh's
# popups snippet)
put_snippet debsway-menu <<'EOF'
# The debsway menu on Super+m (debsway parts/debsway-menu.sh)
bindsym $mod+m exec ~/.local/bin/sway-status --menu
EOF
note "Click \"debsway\" in the bar: Help, Install apps, Update, Status."
note "In a terminal: debsway --help, debsway update, debsway install NAME (Tab lists them; man debsway)."
