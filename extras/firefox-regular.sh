#!/bin/bash
# Firefox as your own user, with friendly defaults: the easy everyday browser,
# for when the sandboxed Firefox's walls get in the way. firefox-regular opens
# Firefox ESR (from Debian) in a profile of its own,
# ~/.mozilla/firefox/debsway-regular, whose user.js (data/firefox-regular-user.js)
# keeps sites fast (the JavaScript JIT on), HTTPS-Only Mode on (one click past
# it), Firefox's standard tracking protection, and nothing sent to Mozilla.
# uBlock Origin (from Debian) blocks ads and trackers.
# It doesn't touch the sandboxed Firefox, incognito or the per-site profiles:
# nothing system-wide is written, only this profile, a firefox-regular command
# and a menu entry. Where Firefox's hardening is set up (with the sandboxed
# Firefox), uBlock's medium mode applies here too: ublock-allow lets a site
# through. It offers to open links from other programs.
# It runs as you, so a hacked page can reach your files: the sandboxed Firefox
# (extras/firefox-sandbox.sh) is the safer one for sites you don't trust.
# Usage: bash firefox-regular.sh [--remove | --manual]
# summary: Firefox as you, friendly defaults (no sandbox)
# status: bin:firefox-regular
# files: data/firefox-regular-user.js data/debsway-firefox-regular.desktop
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

PROFILE=$HOME/.mozilla/firefox/debsway-regular
APP=debsway-firefox-regular.desktop
DESKTOP=$HOME/.local/share/applications/$APP
MIME=$HOME/.config/mimeapps.list

if [ "${1:-}" = --remove ]; then
    remove_bin firefox-regular
    rm -f "$DESKTOP"
    # links go back to whatever opened them before (the sandboxed Firefox, if set up)
    unset_default_app "$APP"
    # Firefox itself stays while another script (the sandbox, incognito) needs it
    apt_purge
    if [ -d "$PROFILE" ]; then
        note "Its profile (logins, history, bookmarks) is in $PROFILE."
        if ask "Delete that profile too?" n; then rm -rf "$PROFILE"; note "Deleted."; fi
    fi
    exit
fi

say "Firefox, for you"
apt_install firefox-esr libavcodec61 webext-ublock-origin-firefox
mkdir -p "$PROFILE"
chmod 700 "$PROFILE"
# A user.js you wrote yourself stays
if [ -f "$PROFILE/user.js" ] && ! grep -qs 'Written by debsway' "$PROFILE/user.js"; then
    note "Kept your own $PROFILE/user.js."
else
    install -m 0600 "$DEBSWAY_DIR/data/firefox-regular-user.js" "$PROFILE/user.js"
fi
install_bin firefox-regular
install -D -m 0644 "$DEBSWAY_DIR/data/$APP" "$DESKTOP"

say "Links from other programs"
# (no mimeapps.list yet is fine: under pipefail a failing sed would end the script)
current=$({ sed -n 's|^x-scheme-handler/https=||p' "$MIME" 2>/dev/null || true; } | head -1)
if [ "$current" = "$APP" ]; then
    note "They already open in firefox-regular."
elif [ "$current" = debsway-firefox.desktop ]; then
    note "They open in the sandboxed Firefox now, which keeps a link's page away from your files."
    if ask "Open them in firefox-regular instead?" n; then
        set_default_app "$APP" x-scheme-handler/http x-scheme-handler/https text/html
    fi
elif ask "Open them in firefox-regular?" y; then
    set_default_app "$APP" x-scheme-handler/http x-scheme-handler/https text/html
fi

note "Run it with: firefox-regular   (or Super+d)"
if [ -f /etc/firefox-esr/debsway-hardening.js ]; then
    note "Firefox's hardening is set up here: uBlock blocks scripts from other sites in"
    note "this profile too. A site that breaks: ublock-allow example.com"
fi
