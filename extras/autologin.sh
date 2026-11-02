#!/bin/bash
# Log in on tty1 without typing your password: the computer starts straight
# into sway (the login loop in ~/.profile starts it on tty1). A systemd drop-in
# for tty1's getty (data/autologin-getty.conf) runs it with --autologin for your
# user; the other consoles still ask. The disk passphrase at boot (if the disk
# is encrypted), the screen lock and sudo all still ask for theirs.
# Without disk encryption, turning the computer on is then enough to be you:
# the script says so, and asks first.
# Takes effect at the next boot.
# Usage: bash autologin.sh [--remove | --manual]
# summary: Log in on tty1 without the password
# security: least
# status: file:/etc/systemd/system/getty@tty1.service.d/50-debsway-autologin.conf
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
. "$DEBSWAY_DIR/lib/install-iso.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user

CONF=/etc/systemd/system/getty@tty1.service.d/50-debsway-autologin.conf
# The root file system's disk is encrypted: some device below / is a LUKS one
# (DEBSWAY_LSBLK_ROOT: a test's answer instead of lsblk's)
root_encrypted() {
    local types
    types=${DEBSWAY_LSBLK_ROOT:-$(lsblk -nso TYPE "$(findmnt -nvo SOURCE /)" 2>/dev/null)}
    grep -qx crypt <<<"$types"
}

if [ "${1:-}" = --remove ]; then
    sudo rm -f "$CONF"
    sudo rmdir "${CONF%/*}" 2>/dev/null || true
    sudo systemctl daemon-reload
    note "tty1 asks for your password again from the next boot."
    exit
fi

user=$(id -un)
autologin_conf "$user" >/dev/null || die "\"$user\" isn't a user name this can set up."
say "Log in on tty1 without the password"
if root_encrypted; then
    note "The disk is encrypted: its passphrase still has to be typed at every boot,"
    note "so someone who has the laptop switched off still can't get in."
else
    warn "This disk is NOT encrypted. With autologin, anyone who switches the computer on"
    warn "is logged in as you, with all your files, and could read the disk without it anyway."
    ask "Log in without the password all the same?" n || die "Nothing was changed."
fi
autologin_conf "$user" | sudo install -D -o root -g root -m 0644 /dev/stdin "$CONF"
sudo systemctl daemon-reload
note "From the next boot, tty1 logs $user in by itself and sway starts."
note "The screen lock (Super+Escape, and after you're idle) still asks for your password, and so does sudo."
note "Undo it with: bash ~/debsway/extras/autologin.sh --remove"
