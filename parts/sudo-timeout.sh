#!/bin/bash
# sudo remembers your password for 60 seconds, in the terminal it was typed
# in, instead of Debian's 15 minutes. A program running as you that waits for
# you to use sudo, to use it in your name right after, gets a minute rather
# than a quarter of an hour, and never another terminal's. Wren Linux's own
# scripts keep working: they refresh it every 50 seconds while they run
# (lib/core.sh sudo_keepalive), so a long install asks once.
# Usage: bash sudo-timeout.sh [--remove]
# status: file:~/.config/wren/sudo-timeout
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

SUDOERS=/etc/sudoers.d/wren-sudo-timeout
# (your user can't look into /etc/sudoers.d, so this says it is set up)
MARK=$HOME/.config/wren/sudo-timeout

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$SUDOERS"
    rm -f "$MARK"
    note "sudo remembers your password for Debian's 15 minutes again."
    exit
fi

say "sudo remembers your password for 60 seconds"
rule=$(mktemp)
printf '%s\n' '# Written by Wren Linux parts/sudo-timeout.sh: sudo remembers your password' \
    '# for one minute, in the terminal it was typed in, not 15.' \
    'Defaults timestamp_timeout=1' 'Defaults timestamp_type=tty' >"$rule"
if ! sudo visudo -cf "$rule" >/dev/null; then
    rm -f "$rule"
    die "The sudoers rule didn't pass visudo's check, so nothing was changed."
fi
sudo install -o root -g root -m 0440 "$rule" "$SUDOERS"
rm -f "$rule"
mkdir -p "${MARK%/*}"
: >"$MARK"
note "Each terminal asks again a minute after its last sudo; Wren Linux's scripts ask once."
