#!/bin/bash
# The "wren" item at the left of the status bar: click it for a black-and-gray
# menu, in a floating, centered window (bin/wren-menu): your browser, password
# manager and terminal, the lists Switches, Apps and System (Install apps, Update,
# Status...), and Help (the key cheat sheet). Arrow keys and Enter choose, or
# click; Esc goes back from a list, and closes the rest. What you choose runs in
# that same window. Super+? still opens the cheat sheet straight away.
# Also the Wren Linux command (wrenctl --help, --update, --apps, wrenctl install
# NAME...), its man page and its Tab completion, so the same things are one
# word away in a terminal.
# Usage: bash wren-menu.sh [--remove]
# status: bin:wren-menu
# files: bin/sway-status data/keys.txt
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

KEYS="$HOME/.local/share/wren/keys.txt"
MAN="$HOME/.local/share/man/man1/wrenctl.1"
# where Debian's bash-completion looks for a user's own completions
COMPLETION="${XDG_DATA_HOME:-$HOME/.local/share}/bash-completion/completions/wrenctl"

if [ "${1:-}" = --remove ]; then
    remove_snippet wren-menu
    remove_bin wren-menu
    remove_bin radios
    remove_bin wrenctl
    rm -f "$MAN" "$COMPLETION"
    # rfkill goes too, unless another script still needs it
    apt_purge
    # The bar keeps its "wren" label; a click then opens the key cheat sheet
    # directly.
    exit
fi

say "Installing the Wren menu"
install_bin wren-menu
# Wi-Fi, Bluetooth and microphone switches (the menu lists the ones this computer has).
# Wi-Fi and Bluetooth are switched with rfkill, which Debian doesn't install by
# itself; without it the menu has no Wi-Fi or Bluetooth line. It needs no sudo:
# udev gives the user at the screen /dev/rfkill.
# (dialog drew the Install apps list for a while; lib/checklist.sh does now,
# with no program of its own, so this script no longer wants it)
apt_drop dialog
apt_install rfkill
install_bin radios
# the Wren Linux command and man wrenctl (man-db finds ~/.local/share/man from ~/.local/bin)
install_bin wrenctl
install -D -m 0644 "$WREN_DIR/data/wrenctl.1" "$MAN"
# Tab completes wrenctl install NAME (and the options) in a new terminal
install -D -m 0644 "$WREN_DIR/data/wrenctl-completion.bash" "$COMPLETION"
# the cheat sheet command: shows it with the menu's pager, so Esc closes it
install_bin keys
# The bar (the "wren" item) and the cheat sheet that mentions it
install_bin sway-status
mkdir -p "${KEYS%/*}"
install -m 0644 "$WREN_DIR/data/keys.txt" "$KEYS"
# Super+m, as a click on "wren" in the bar: again closes it. Here, not in
# install-base.sh, so update.sh brings it to an install made before it (an
# earlier version's window rule in this snippet now lives in install-base.sh's
# popups snippet)
put_snippet wren-menu <<'EOF'
# The Wren menu on Super+m (Wren Linux parts/wren-menu.sh)
bindsym $mod+m exec ~/.local/bin/sway-status --menu
EOF
note "Click \"Wren Linux\" in the bar: Switches, Apps, System (Install apps, Update, Status), Help."
note "In a terminal: wrenctl --help, wrenctl update, wrenctl install NAME (Tab lists them; man wrenctl)."
