#!/bin/bash
# Mullvad VPN, from Mullvad's own apt repository: the "mullvad" command,
# the background service it talks to, and the graphical app. You need a
# Mullvad account number (mullvad.net, can be paid anonymously).
# Usage: bash mullvad-vpn.sh [--remove]
# summary: Mullvad VPN app and command
# status: apt:mullvad-vpn
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/mullvad-repo.sh"
need_user

if [ "${1:-}" = --remove ]; then
    if command -v mullvad >/dev/null; then mullvad disconnect >/dev/null 2>&1 || true; fi
    apt_purge mullvad-vpn
    remove_bin mullvad-vpn
    remove_mullvad_repo_if_unused
    exit
fi

say "Mullvad apt repository"
add_mullvad_repo

say "Installing Mullvad VPN"
apt_install mullvad-vpn
# The app lives in /opt and isn't on PATH; this makes Super+d find it
install_bin mullvad-vpn

cat <<'EOF'

    How to use the mullvad command:
      mullvad account login 1234123412341234    log in with your account number
      mullvad relay set location se             choose a country (se = Sweden)
      mullvad relay set location se mma         ... or a city (Malmö)
      mullvad relay list                        all countries, cities and servers
      mullvad connect                           connect
      mullvad status                            connected? where to?
      mullvad disconnect                        disconnect
      mullvad auto-connect set on               connect whenever the laptop starts
      mullvad lockdown-mode set on              block all internet while the VPN
                                                is off (also blocks Tor Browser)
      mullvad dns set default --block-ads --block-trackers --block-malware
                                                Mullvad's DNS blocks ads and trackers
      mullvad lan set allow                     still reach printers etc. at home

    The graphical app: mullvad-vpn   (or Super+d)
EOF
