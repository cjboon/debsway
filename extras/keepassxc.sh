#!/bin/bash
# KeePassXC, a password manager that keeps everything in one encrypted
# file you control. It asks first whether you want the KeePassXC-Browser
# extension for Firefox (webext-keepassxc-browser). Only the full build
# (keepassxc-full) has the browser integration the extension talks to, so:
#   yes -> keepassxc-full and the extension
#   no  -> keepassxc-minimal, the smaller build without it
# qtwayland5 lets it run on Wayland without XWayland. Run it again to
# switch between the two.
# Usage: bash keepassxc.sh [--remove]
# summary: KeePassXC password manager (Firefox add-on optional)
# status: apt:keepassxc-full apt:keepassxc-minimal apt:keepassxc
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
need_user

if [ "${1:-}" = --remove ]; then
    apt_purge keepassxc-full keepassxc-minimal keepassxc webext-keepassxc-browser
    note "Your password databases (.kdbx files) are left where they are."
    exit
fi

say "KeePassXC"
# Already there counts as a yes, so running this again doesn't take it away
want_web=false
if is_installed webext-keepassxc-browser; then
    want_web=true
elif ask "Do you want the KeePassXC-Browser extension for Firefox (fills in logins from your database)?" n; then
    want_web=true
fi

# The two builds conflict: apt swaps one for the other
if $want_web; then
    pkgs=(keepassxc-full qtwayland5 webext-keepassxc-browser)
    apt_drop keepassxc-minimal keepassxc
    if is_installed keepassxc-minimal; then note "Replacing keepassxc-minimal with keepassxc-full, which the extension needs."; fi
else
    pkgs=(keepassxc-minimal qtwayland5)
    apt_drop keepassxc-full keepassxc webext-keepassxc-browser
    if is_installed keepassxc-full; then note "Replacing keepassxc-full with keepassxc-minimal (no browser integration)."; fi
fi
apt_install "${pkgs[@]}"
note "Run it with: keepassxc   (or Super+d)"
note "It can also generate two-factor login codes (TOTP) for your accounts."
if $want_web; then
    note "To fill in logins in Firefox: in KeePassXC, Tools > Settings > Browser Integration,"
    note "turn it on and tick Firefox; then restart Firefox and click the extension's icon."
fi
