#!/bin/bash
# One workspace: Super+1 … 0 and Super+Shift+1 … 0 do nothing, and the bar
# shows no workspace buttons, so every window stays on the one screen you
# see. An external screen still gets its own. Taken out with --remove, the
# keys and buttons come back. make-install-iso.sh --simplesway ticks it in
# the first install list.
# Usage: bash one-workspace.sh [--remove | --manual]
# summary: One workspace: no workspace keys or buttons
# security: some
# status: file:~/.config/sway/config.d/one-workspace.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet one-workspace
    note "Workspaces are back: Super+1 … 0, and their buttons in the bar."
    exit
fi

say "One workspace"
{
    echo "# One workspace (debsway extras/one-workspace.sh)"
    for k in 1 2 3 4 5 6 7 8 9 0; do
        echo "unbindsym \$mod+$k"
        echo "unbindsym \$mod+Shift+$k"
    done
    # bar-0: the stock config's bar, the one debsway's status line is in
    echo "bar bar-0 workspace_buttons no"
} | put_snippet one-workspace
note "Super+1 … 0 now do nothing, and the bar shows no workspace buttons."
