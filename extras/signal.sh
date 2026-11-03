#!/bin/bash
# Signal Desktop, from Signal's own apt repository: end-to-end encrypted
# messages and calls, linked to the Signal account on your phone. The
# repository key is only trusted if it is exactly SIGNAL_FPR (pins.sh), and
# unattended-upgrades installs its updates. (SimpleX Chat, extras/simplex-chat.sh,
# needs no phone number; Signal does.)
# Signal is an Electron app. Its package makes Electron's sandbox helper
# (/opt/Signal/chrome-sandbox) setuid root; Debian lets Electron sandbox itself
# without that, so this takes the setuid bit off, for good (dpkg-statoverride,
# which updates keep).
# Usage: bash signal.sh [--remove | --manual]
# summary: Signal Desktop messenger (signed apt repo)
# security: some
# status: apt:signal-desktop
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

KEY=/usr/share/keyrings/signal-desktop-keyring.asc
LIST=/etc/apt/sources.list.d/signal-desktop.list
HELPER=/opt/Signal/chrome-sandbox

if [ "${1:-}" = --remove ]; then
    apt_purge signal-desktop
    if dpkg-statoverride --list "$HELPER" >/dev/null 2>&1; then sudo dpkg-statoverride --remove "$HELPER" >/dev/null; fi
    sudo rm -f "$LIST" "$KEY"
    forget_unattended_updates signal
    note "Your messages and the link to your phone stay in ~/.config/Signal; delete that folder to unlink this computer."
    exit
fi

say "Signal's apt repository"
install_apt_key "$SIGNAL_FPR" "$SIGNAL_KEY_URL" "$KEY"
echo "deb [arch=amd64 signed-by=$KEY] https://updates.signal.org/desktop/apt xenial main" |
    sudo tee "$LIST" >/dev/null
allow_unattended_updates signal updates.signal.org
# A fresh update, so apt sees the new repository
unset WREN_APT_UPDATED

say "Its sandbox helper without setuid root"
# Before the install, so the package's own setup already leaves it this way
dpkg-statoverride --list "$HELPER" >/dev/null 2>&1 ||
    sudo dpkg-statoverride --add root root 0755 "$HELPER"

say "Installing Signal"
apt_install signal-desktop
if [ -e "$HELPER" ] && [ -u "$HELPER" ]; then sudo chmod 0755 "$HELPER"; fi

note "Run it with: signal-desktop   (or Super+d, or the Wren menu)"
note "The first time, it shows a QR code: scan it with Signal on your phone"
note "(Settings > Linked devices) to link this computer."
