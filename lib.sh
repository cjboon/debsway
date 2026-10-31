# shellcheck shell=bash
# lib.sh: shared helpers, sourced by every debsway script. They are split
# by topic in lib/; a script that needs one of the app helpers sources it
# itself (lib/appimage.sh, lib/mullvad-repo.sh, lib/firefox-profiles.sh).
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

DEBSWAY_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Signing keys and versions debsway trusts, each with the date it was checked
. "$DEBSWAY_DIR/pins.sh"
. "$DEBSWAY_DIR/lib/core.sh"
. "$DEBSWAY_DIR/lib/apt.sh"
. "$DEBSWAY_DIR/lib/sway.sh"
. "$DEBSWAY_DIR/lib/net.sh"
. "$DEBSWAY_DIR/lib/tor.sh"
. "$DEBSWAY_DIR/lib/mime.sh"
