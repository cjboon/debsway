#!/bin/bash
# Automatic security updates: every day apt quietly installs Debian's
# security fixes (and Debian's own stable fixes) in the background.
# Debian's default rules are kept. Packages from the other apt repositories
# Wren Linux adds (Mullvad, Claude Code, Signal, the Tor Project) are updated too: the script that adds
# a repository allows it (allow_unattended_updates in lib/apt.sh). Any
# repository you add yourself is left for you to update. What it did is
# logged in /var/log/unattended-upgrades/.
# It also says when they stop working: if the daily download fails while you're online (a mirror
# down, a Tor bridge gone), or nothing has been fetched for days, the bar shows it, with a
# notification. Being offline isn't a failure. Your own apt-get runs aren't made any stricter.
# Usage: bash unattended-upgrades.sh [--remove]
# files: bin/wren-update-result
# status: apt:unattended-upgrades
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

CONF=/etc/apt/apt.conf.d/20auto-upgrades
HELPER=/usr/local/libexec/wren-update-result
STRICT=/etc/wren/apt-daily.conf
DROPIN=/etc/systemd/system/apt-daily.service.d/60-wren-update-result.conf

if [ "${1:-}" = --remove ]; then
    apt_purge unattended-upgrades
    sudo rm -f "$CONF" "$HELPER" "$STRICT" "$DROPIN"
    sudo rmdir "${DROPIN%/*}" /usr/local/libexec /etc/wren 2>/dev/null || true
    sudo rm -rf /run/wren-updates
    sudo systemctl daemon-reload >/dev/null 2>&1 || true
    note "Automatic updates are off. Update yourself with: sudo apt update && sudo apt upgrade"
    exit
fi

say "Installing unattended-upgrades"
apt_install unattended-upgrades
# The package normally writes this too; written here so it's on for sure
printf '%s\n' 'APT::Periodic::Update-Package-Lists "1";' 'APT::Periodic::Unattended-Upgrade "1";' |
    sudo tee "$CONF" >/dev/null
# Whether they keep working: only the daily job is strict about failed downloads (a stricter
# apt-get everywhere would stop every install while one repository is down)
sudo install -d -o root -g root -m 0755 "${HELPER%/*}" "${STRICT%/*}" "${DROPIN%/*}"
sudo install -o root -g root -m 0755 "$WREN_DIR/bin/wren-update-result" "$HELPER"
printf '%s\n' '// Written by Wren Linux parts/unattended-upgrades.sh: for the daily job only' \
    'APT::Update::Error-Mode "any";' | sudo tee "$STRICT" >/dev/null
printf '%s\n' '# Written by Wren Linux parts/unattended-upgrades.sh' '[Service]' \
    "Environment=APT_CONFIG=$STRICT" "ExecStopPost=-$HELPER" | sudo tee "$DROPIN" >/dev/null
sudo systemctl daemon-reload >/dev/null 2>&1 || true
sudo systemctl enable --now apt-daily.timer apt-daily-upgrade.timer >/dev/null 2>&1 || true
note "Security updates install themselves daily. See what would update: sudo unattended-upgrade --dry-run"
