#!/bin/bash
# Hints for commands that aren't installed: type the name of a debsway
# extra's command that isn't set up (claude-vm, gimp, mpv...) and the terminal
# says which script installs it. It only prints; nothing is installed or run.
# A root-owned file (data/command-hints.bash) that one marked line in your
# ~/.bashrc loads; bash calls it only when no program of that name exists.
# Usage: bash command-hints.sh [--remove]
# files: data/command-hints.bash
# status: file:/usr/local/share/debsway/command-hints.bash
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

HINTS=/usr/local/share/debsway/command-hints.bash
RC=$HOME/.bashrc
BEGIN='# >>> debsway command hints >>>'
END='# <<< debsway command hints <<<'

take_out() { [ -f "$RC" ] && sed -i "\\|^$BEGIN\$|,\\|^$END\$|d" "$RC"; return 0; }

if [ "${1:-}" = --remove ]; then
    take_out
    sudo rm -f "$HINTS"
    sudo rmdir /usr/local/share/debsway 2>/dev/null || true
    note "Gone from new terminals."
    exit
fi

say "Hints for commands that aren't installed"
sed "s|@DEBSWAY_DIR@|$(printf '%q' "$DEBSWAY_DIR")|" "$DEBSWAY_DIR/data/command-hints.bash" |
    sudo install -D -o root -g root -m 0644 /dev/stdin "$HINTS"
take_out
printf '%s\n' "$BEGIN" "[ -r $HINTS ] && . $HINTS" "$END" >>"$RC"
note "New terminals say which debsway script installs a command that's missing."
