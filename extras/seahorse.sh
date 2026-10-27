#!/bin/bash
# Seahorse ("Passwords and Keys") with the GNOME keyring it manages.
# The keyring is unlocked with your login password when you log in on
# the console, so apps that store secrets (like gh) don't ask again.
# Usage: bash seahorse.sh [--remove]
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

PAM=/etc/pam.d/login
AUTH='auth       optional   pam_gnome_keyring.so'
SESSION='session    optional   pam_gnome_keyring.so auto_start'

if [ "${1:-}" = --remove ]; then
    if [ -f "$PAM" ]; then
        tmp=$(mktemp)
        grep -vxF -e "$AUTH" -e "$SESSION" "$PAM" >"$tmp" || true
        # shellcheck disable=SC2024  # tee writes as root; the temp file is ours
        sudo tee "$PAM" <"$tmp" >/dev/null
        rm -f "$tmp"
        note "Removed the keyring lines from $PAM"
    fi
    apt_purge seahorse gnome-keyring libpam-gnome-keyring
    note "Your keyrings are kept in ~/.local/share/keyrings."
    note "Apps that saved secrets there (like gh) will ask you to log in again."
    exit
fi

say "Installing seahorse and gnome-keyring"
apt_install seahorse gnome-keyring libpam-gnome-keyring

say "Unlock the keyring at login"
[ -e "$PAM.debsway.bak" ] || sudo cp -a "$PAM" "$PAM.debsway.bak"
if ! sudo grep -qxF "$AUTH" "$PAM"; then
    sudo sed -i "/^@include common-auth/a $AUTH" "$PAM"
fi
if ! sudo grep -qxF "$SESSION" "$PAM"; then
    sudo sed -i "/^@include common-session/a $SESSION" "$PAM"
fi
sudo grep -n gnome_keyring "$PAM" | sed 's/^/    /'
note "Takes effect at your next console login. Run it with: seahorse"
