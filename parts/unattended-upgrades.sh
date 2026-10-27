#!/bin/bash
# Automatic security updates: every day apt quietly installs Debian's
# security fixes (and Debian's own stable fixes) in the background.
# Debian's default rules are kept, so packages from other repos (Claude
# Code, Mullvad) are left for you to update. What it did is logged in
# /var/log/unattended-upgrades/.
# Usage: bash unattended-upgrades.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/apt/apt.conf.d/20auto-upgrades

if [ "${1:-}" = --remove ]; then
    apt_purge unattended-upgrades
    sudo rm -f "$CONF"
    note "Automatic updates are off. Update yourself with: sudo apt update && sudo apt upgrade"
    exit
fi

say "Installing unattended-upgrades"
apt_install unattended-upgrades
# The package normally writes this too; written here so it's on for sure
printf '%s\n' 'APT::Periodic::Update-Package-Lists "1";' 'APT::Periodic::Unattended-Upgrade "1";' |
    sudo tee "$CONF" >/dev/null
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
note "Security updates install themselves daily. See what would update: sudo unattended-upgrade --dry-run"
