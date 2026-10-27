#!/bin/bash
# Firefox ESR, set up the debsway way: video codecs (libavcodec61), uBlock
# Origin from Debian in "medium mode", HTTPS-Only Mode, the JavaScript JIT
# off and a notice when it needs a restart after an update
# (parts/firefox-hardening.sh); then, if you want it, the throwaway
# "incognito" Firefox in its own locked-down user (parts/incognito.sh).
# Usage: bash firefox.sh [--remove]
# summary: Firefox ESR with hardening and uBlock Origin
# status: apt:firefox-esr
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    bash "$DEBSWAY_DIR/parts/incognito.sh" --remove
    bash "$DEBSWAY_DIR/parts/firefox-hardening.sh" --remove
    apt_purge firefox-esr libavcodec61 webext-ublock-origin-firefox
    note "Your Firefox profiles (bookmarks, logins) stay in ~/.mozilla and ~/.config/mozilla."
    exit
fi

say "Installing Firefox ESR"
apt_install firefox-esr libavcodec61 webext-ublock-origin-firefox

bash "$DEBSWAY_DIR/parts/firefox-hardening.sh"

say "incognito"
note "incognito opens a throwaway Firefox as a separate, locked-down user, with"
note "its own clipboard, no shared folders, sound and video, and nothing kept."
if ask "Set it up too?" y; then
    bash "$DEBSWAY_DIR/parts/incognito.sh"
else
    note "Later: bash parts/incognito.sh"
fi
note "Run Firefox with: firefox-esr   (or Super+d)"
