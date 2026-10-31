#!/bin/bash
# If you set a root password in the installer, Debian leaves sudo out.
# Run this once as root to install it and let your user use it:
#   su -
#   bash /path/to/debsway/prep/setup-sudo.sh USERNAME
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

[ "$(id -u)" -eq 0 ] || die "Run as root: su -   then: bash $DEBSWAY_DIR/prep/setup-sudo.sh USERNAME"

user=${1:-}
if [ -z "$user" ]; then
    user=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }' /etc/passwd)
    if [ -n "$user" ]; then
        tty_read pick "Give sudo to which user? [$user] "
        user=${pick:-$user}
    else
        note "No regular user account found; create one first (adduser NAME)."
        tty_read user "Give sudo to which user? "
    fi
    [ -n "$user" ] || die "No user given. Run: bash $DEBSWAY_DIR/prep/setup-sudo.sh USERNAME"
fi
id "$user" >/dev/null 2>&1 || die "No user called $user."

if ! command -v sudo >/dev/null; then
    have_internet || die "No internet. Run first: bash $DEBSWAY_DIR/wifi.sh"
    apt-get update
    apt-get install -y --no-install-recommends sudo
fi
adduser "$user" sudo
say "Done. $user must log out and back in before sudo works."
note "Once sudo works, lock the root password (no one can log in as root, sudo is unaffected):"
note "  sudo passwd -l root"
