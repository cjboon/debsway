#!/bin/bash
# After an update, programs that are still running keep using the old,
# unfixed library until they restart. needrestart checks for that after
# every apt run and lists what needs a restart; it only lists, and never
# restarts anything for you (a restart in the middle of your work, or of
# NetworkManager, would be worse than the wait). It can also pop up a
# desktop notification (libnotify-bin is installed for that).
# Run it yourself any time: sudo needrestart
# Usage: bash needrestart.sh [--remove]
# status: file:/etc/needrestart/conf.d/50-debsway.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/needrestart/conf.d/50-debsway.conf

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$CONF"
    apt_purge needrestart libnotify-bin
    exit
fi

say "Installing needrestart"
apt_install needrestart libnotify-bin
sudo install -d -o root -g root -m 0755 "${CONF%/*}"
printf '%s\n' '# Written by debsway parts/needrestart.sh' \
    "# List what needs a restart; never restart anything automatically" \
    "\$nrconf{restart} = 'l';" | sudo tee "$CONF" >/dev/null
note "It lists what needs a restart after each update. Check any time with: sudo needrestart"
