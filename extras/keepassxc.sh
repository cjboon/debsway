#!/bin/bash
# KeePassXC, a password manager that keeps everything in one encrypted
# file you control. It is the minimal build (keepassxc-minimal): no browser
# integration, no KeePassXC-Browser add-on for Firefox. Copy and paste a
# password or use auto-type instead; that keeps a web page, and the sandboxed
# Firefox, from having any way to talk to the password manager.
# qtwayland5 lets it run on Wayland without XWayland. Running this on a
# computer that has the full build (keepassxc-full, with webext-keepassxc-browser)
# switches it to the minimal one.
#  - It locks its databases whenever the screen locks (Super+Escape, the idle
#    lock, the lid, before sleep): an on-lock program,
#    ~/.config/wren/on-lock.d/keepassxc, runs keepassxc --lock.
#  - It can open on workspace 1 at every login (it asks).
# Usage: bash keepassxc.sh [--remove | --manual]
# summary: KeePassXC password manager (no browser add-on)
# security: most
# status: apt:keepassxc-full apt:keepassxc-minimal apt:keepassxc
# files: lib/sway.sh
. "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"
if [ "${1:-}" = --manual ]; then print_manual; exit; fi
need_user
HOOK=${XDG_CONFIG_HOME:-$HOME/.config}/wren/on-lock.d/keepassxc

if [ "${1:-}" = --remove ]; then
    rm -f "$HOOK"
    remove_snippet keepassxc-start
    apt_purge keepassxc-full keepassxc-minimal keepassxc webext-keepassxc-browser
    note "Your password databases (.kdbx files) are left where they are."
    exit
fi

say "KeePassXC"
# The builds conflict: apt swaps one for the other. The add-on goes with the full build.
apt_drop keepassxc-full keepassxc webext-keepassxc-browser
if is_installed keepassxc-full || is_installed webext-keepassxc-browser; then
    note "Replacing keepassxc-full and the Firefox add-on with keepassxc-minimal (no browser integration)."
fi
apt_install keepassxc-minimal qtwayland5

say "Locked whenever the screen locks"
# (only if it runs: keepassxc --lock would start it otherwise)
mkdir -p "${HOOK%/*}"
# shellcheck disable=SC2016  # written into the program as it is, expanded when it runs
printf '%s\n' '#!/bin/sh' '# Written by Wren Linux extras/keepassxc.sh: the screen locks, so KeePassXC'"'"'s databases do too' \
    'pgrep -x -u "$(id -u)" keepassxc >/dev/null || exit 0' 'exec keepassxc --lock' >"$HOOK"
chmod 755 "$HOOK"
note "Whenever the screen locks, KeePassXC locks its open databases: the passwords"
note "need the master password again, so neither someone at the screen nor a program"
note "of yours can read them while you're away."

if ask "Open KeePassXC on workspace 1 at every login?" y; then
    put_snippet keepassxc-start <<'EOF'
# KeePassXC on workspace 1 at login (Wren Linux extras/keepassxc.sh)
exec sh -c 'swaymsg -q "workspace number 1"; exec keepassxc'
EOF
    note "It opens on workspace 1 from your next login."
else
    remove_snippet keepassxc-start
fi
note "Run it with: keepassxc   (or Super+d)"
note "It can also generate two-factor login codes (TOTP) for your accounts."
note "To use a password on a web page: copy it from KeePassXC (Ctrl+C) and paste it."
