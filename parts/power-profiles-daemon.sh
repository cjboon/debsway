#!/bin/bash
# Power profiles (power-saver / balanced / performance) for better
# battery life. It runs as a system service and starts on balanced.
# Usage: bash power-profiles-daemon.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge power-profiles-daemon
    exit
fi

# tlp does the same job; running both makes them fight
# Warn and skip rather than fail, so install-base.sh carries on
if is_installed tlp; then
    warn "tlp is installed and already manages power; skipping power-profiles-daemon."
    exit 0
fi

say "Installing power-profiles-daemon"
apt_install power-profiles-daemon
sudo systemctl enable --now power-profiles-daemon.service

note "Current profile: $(powerprofilesctl get 2>/dev/null || echo unknown)"
note "Change it: powerprofilesctl set power-saver | balanced | performance"
