#!/bin/bash
# Mullvad Browser, from Mullvad's apt repository: made by the Tor Project
# and Mullvad, with Tor Browser's protections against tracking and
# fingerprinting but without Tor. Meant for use with a VPN (Mullvad's or
# another), and it forgets everything when closed. It's built on Tor
# Browser, which runs on X11, so XWayland is installed. "-regular" as in
# firefox-regular: it runs as you, with no sandbox from debsway.
# Usage: bash mullvad-browser-regular.sh [--remove | --manual]
# summary: Mullvad Browser, as you (no Tor: use a VPN)
# security: some
# status: apt:mullvad-browser
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/mullvad-repo.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user
# Its package marker keeps the name it had as extras/mullvad-browser.sh, so a
# computer that installed it then still has it held, and --remove finds it
export DEBSWAY_OWNER=mullvad-browser

if [ "${1:-}" = --remove ]; then
    apt_purge mullvad-browser
    remove_mullvad_repo_if_unused
    exit
fi

say "Mullvad apt repository"
add_mullvad_repo

say "Installing Mullvad Browser"
need_xwayland
apt_install mullvad-browser
note "Run it with: mullvad-browser   (or Super+d)"
note "It doesn't hide your IP address by itself: connect a VPN first."
