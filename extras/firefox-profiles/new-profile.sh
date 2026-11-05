#!/bin/bash
# A separate Firefox profile for one website, with its own cookies, logins and
# settings, and a command that opens it: NAME (e.g. github), or firefox-NAME
# when a program is called NAME already. Each profile also gets a
# locked-down Linux user of its own (fx-NAME), like the sandboxed Firefox's: a
# hacked page in one profile reaches neither your files nor the other profiles.
# Only the clipboard and ~/Downloads/NAME are shared with you. It needs the
# sandboxed Firefox (extras/firefox-sandbox.sh), and offers to set that up.
# The window shows only the page: no tabs, address bar or bookmarks bar.
#
#   bash new-profile.sh                       asks: a ready-made one, or your own name and address
#   bash new-profile.sh NAME                  a ready-made one (github, tutamail, chess...)
#   bash new-profile.sh --list                the ready-made ones (data/firefox-profiles.list)
#   bash new-profile.sh NAME URL [--fast-js] [--show-toolbars] [--no-sound] [--delete-cookies]
#                                             e.g. bash new-profile.sh bank https://mybank.example
#   bash new-profile.sh --remove NAME         removes its command; asks whether to delete the profile and its user
#   bash new-profile.sh --manual              prints the steps to make one by hand
#
# --fast-js turns the JavaScript JIT back on for this profile (Wren Linux's
# parts/firefox-hardening.sh turns it off everywhere), for heavy web apps.
# --show-toolbars keeps Firefox's tabs and address bar for this profile.
# --no-sound: no sound from it (a bank needs none; a video site does).
# --delete-cookies: its cookies, site data and cache go when it closes (logged
# out each time); without it they are kept, so you stay logged in.
# Run without NAME and URL, it asks, fast JavaScript, sound and cookies included.
# A ready-made one comes with settings chosen for its site, and the sites
# uBlock's medium mode would break it on are allowed (ublock-allow): those
# load their own code from a second domain. Removing the profile leaves them.
. "$(dirname -- "${BASH_SOURCE[0]}")/../../lib.sh"
. "$WREN_DIR/lib/firefox-sandbox.sh"
. "$WREN_DIR/lib/firefox-profiles.sh"
if [ "${1:-}" = --manual ]; then print_manual firefox-profiles; exit; fi
not_root

valid_name() { fx_profile_name_ok "$1"; }
# Only characters that are safe in a web address and in the launcher
valid_url() { [[ $1 =~ ^https?://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~/?#=%+,@-]*)?$ ]]; }

if [ "${1:-}" = --remove ]; then
    [ $# -eq 2 ] && valid_name "$2" || die "Usage: bash new-profile.sh --remove NAME"
    remove_profile "$2"
    exit
fi

if [ "${1:-}" = --list ]; then
    echo "Ready-made profiles (bash new-profile.sh NAME):"
    fx_catalog_list
    exit
fi

fast=no toolbars=hidden sound=yes cookies=keep allow=-
args=$#
# ready NAME: the ready-made profile NAME's settings, or fails
ready() {
    local line
    line=$(fx_catalog "$1") || return 1
    name=$1
    read -r url fast toolbars sound cookies allow <<<"$line"
}
if [ $# -eq 1 ]; then
    ready "$1" || die "There is no ready-made profile called \"$1\" (bash new-profile.sh --list). For your own: bash new-profile.sh NAME URL"
elif [ $# -ge 2 ]; then
    name=$1 url=$2
    shift 2
    for opt in "$@"; do
        case $opt in
            --fast-js) fast=yes ;;
            --show-toolbars) toolbars=shown ;;
            --no-sound) sound=no ;;
            --delete-cookies) cookies=delete ;;
            *) die "Usage: bash new-profile.sh NAME URL [--fast-js] [--show-toolbars] [--no-sound] [--delete-cookies]" ;;
        esac
    done
else
    note "Ready-made: $(awk '!/^#/ && NF { printf "%s ", $1 }' "$FX_CATALOG")"
    note "(what each is: bash new-profile.sh --list)"
    note "Type one of those, or a name of your own (lowercase letters, digits and dashes, e.g. bank)."
    tty_read name "    name> "
fi
if [ "$args" -eq 0 ] && ready "$name"; then
    note "$name: the ready-made settings."
elif [ "$args" -eq 0 ]; then
    tty_read url "    address (e.g. https://mybank.example)> "
    note "Fast JavaScript makes heavy sites quicker (web mail, office, chat), but the"
    note "part that does it (the JIT) is where many browser attacks happen. Off, the"
    note "site still works, just slower: keep it off unless this site feels sluggish."
    if ask "Fast JavaScript for this site?" n; then
        fast=yes
    fi
    if ! ask "Sound from this site (videos, music)? It can't hear your microphone either way." y; then
        sound=no
    fi
    note "Cookies and site data are what keep you logged in to this site."
    note "  keep    they stay when it closes: you stay logged in (most profiles want this)"
    note "  delete  they go when it closes: logged out each time, and the site can't"
    note "          recognise you from one visit to the next (saved passwords still fill in)"
    choose cookies "When this profile closes, its cookies and site data:" keep keep delete
fi
valid_name "$name" || die "\"$name\" isn't a usable name: lowercase letters, digits and dashes, starting with a letter, at most 28 long (and not esr, restart-check or session)."
[[ $url == *:* ]] || url="https://$url"
valid_url "$url" || die "\"$url\" doesn't look like a web address."

make_profile "$name" "$url" "$fast" "$toolbars" "$sound" "$cookies"

# Sites this one needs to load other sites' scripts on (uBlock's medium mode;
# a test puts a pretend ublock-allow in its place)
UBLOCK_ALLOW=${WREN_UBLOCK_ALLOW:-/usr/local/bin/ublock-allow}
if [ "$allow" != - ]; then
    for site in ${allow//,/ }; do
        if [ -x "$UBLOCK_ALLOW" ]; then
            "$UBLOCK_ALLOW" "$site" >/dev/null && note "uBlock: $site may load its own code from its other domains (ublock-allow --list)."
        fi
    done
fi
