#!/bin/bash
# If you set a root password in the installer, Debian leaves sudo out.
# Run this once as root to install it and let your user use it:
#   su -
#   bash /path/to/debsway/setup-sudo.sh USERNAME
. "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

[ "$(id -u)" -eq 0 ] || die "Run as root: su -   then: bash $DEBSWAY_DIR/setup-sudo.sh USERNAME"

user=${1:-}
if [ -z "$user" ]; then
    user=$(awk -F: '$3 >= 1000 && $3 < 60000 { print $1; exit }' /etc/passwd)
    read -r -p "Give sudo to which user? [$user] " pick </dev/tty || pick=
    user=${pick:-$user}
fi
id "$user" >/dev/null 2>&1 || die "No user called $user."

if ! command -v sudo >/dev/null; then
    have_internet || die "No internet. Run first: bash $DEBSWAY_DIR/wifi.sh"
    apt-get update
    apt-get install -y --no-install-recommends sudo
fi
adduser "$user" sudo
say "Done. $user must log out and back in before sudo works."
