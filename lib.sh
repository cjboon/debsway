# shellcheck shell=bash
# lib.sh: shared helpers, sourced by every Wren Linux script. They are split
# by topic in lib/; a script that needs one of the app helpers sources it
# itself (lib/appimage.sh, lib/mullvad-repo.sh, lib/firefox-profiles.sh).
set -euo pipefail
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WREN_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
# Signing keys and versions Wren Linux trusts, each with the date it was checked
. "$WREN_DIR/pins.sh"
. "$WREN_DIR/lib/core.sh"
. "$WREN_DIR/lib/apt.sh"
. "$WREN_DIR/lib/sway.sh"
. "$WREN_DIR/lib/net.sh"
. "$WREN_DIR/lib/tor.sh"
. "$WREN_DIR/lib/mime.sh"
