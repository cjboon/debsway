#!/bin/bash
# What opens when you log in, and on which workspace, all in one file you can
# change: ~/.config/wren/autostart, a workspace and a command on each line (it
# starts with a terminal on workspace 2). bin/wren-autostart starts them, and
# changes the file for you: the Wren menu's System > Startup programs, or
# wren-autostart edit. A program's script that offers to open at login
# (extras/keepassxc.sh) adds its line here too. Your file is never replaced.
# Usage: bash autostart.sh [--remove]
# status: bin:wren-autostart
# files: bin/wren-autostart data/autostart lib/sway.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    remove_snippet autostart
    remove_bin wren-autostart
    note "Nothing opens by itself at login now. Your list stays in $AUTOSTART_FILE."
    exit
fi

say "What opens at login"
autostart_ensure
# KeePassXC had a line of its own in sway's config before this file
if [ -f "$SWAY_SNIPPETS/keepassxc-start.conf" ]; then
    "$BIN/wren-autostart" add 1 keepassxc
    remove_snippet keepassxc-start
fi
note "$AUTOSTART_FILE says what opens where:"
"$BIN/wren-autostart" list
note "Change it: the Wren menu's System > Startup programs, or wren-autostart edit"
