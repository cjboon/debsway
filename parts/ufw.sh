#!/bin/bash
# Firewall: block everything coming in, allow everything going out.
# Usage: bash ufw.sh [--remove]
# status: apt:ufw
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    if command -v ufw >/dev/null; then sudo ufw disable; fi
    apt_purge ufw
    exit
fi

say "Installing ufw"
apt_install ufw

sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw --force enable
sudo ufw status verbose | sed 's/^/    /'
note "Open a port later with e.g.: sudo ufw allow 22/tcp"
