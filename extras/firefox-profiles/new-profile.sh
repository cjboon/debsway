#!/bin/bash
# A separate Firefox profile for one website, with its own cookies, logins and
# settings, and a firefox-NAME command that opens it. Each profile also gets a
# locked-down Linux user of its own (fx-NAME), like the sandboxed Firefox's: a
# hacked page in one profile reaches neither your files nor the other profiles.
# Only the clipboard and ~/Downloads/NAME are shared with you. It needs the
# sandboxed Firefox (extras/firefox-sandbox.sh), and offers to set that up.
#
#   bash new-profile.sh                       asks for the name and address
#   bash new-profile.sh NAME URL [--fast-js]  e.g. bash new-profile.sh bank https://mybank.example
#   bash new-profile.sh --remove NAME         removes firefox-NAME; asks whether to delete the profile and its user
#
# --fast-js turns the JavaScript JIT back on for this profile (debsway's
# parts/firefox-hardening.sh turns it off everywhere), for heavy web apps.
. "$(dirname -- "${BASH_SOURCE[0]}")/../../lib.sh"
. "$DEBSWAY_DIR/lib/firefox-sandbox.sh"
. "$DEBSWAY_DIR/lib/firefox-profiles.sh"
not_root

valid_name() { fx_profile_name_ok "$1"; }
# Only characters that are safe in a web address and in the launcher
valid_url() { [[ $1 =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/?#=%+,@-]*)?$ ]]; }

if [ "${1:-}" = --remove ]; then
    [ $# -eq 2 ] && valid_name "$2" || die "Usage: bash new-profile.sh --remove NAME"
    remove_profile "$2"
    exit
fi

fast=no
if [ $# -ge 2 ]; then
    name=$1 url=$2
    [ "${3:-}" = --fast-js ] && fast=yes
else
    note "A name for the profile: lowercase letters, digits and dashes, e.g. bank."
    tty_read name "    name> "
    tty_read url "    address (e.g. https://mybank.example)> "
    if ask "Fast JavaScript for this site? Only for heavy web apps (mail, office, chat) that feel slow" n; then
        fast=yes
    fi
fi
valid_name "$name" || die "\"$name\" isn't a usable name: lowercase letters, digits and dashes, starting with a letter, at most 28 long."
[[ $url == *:* ]] || url="https://$url"
valid_url "$url" || die "\"$url\" doesn't look like a web address."

make_profile "$name" "$url" "$fast"
